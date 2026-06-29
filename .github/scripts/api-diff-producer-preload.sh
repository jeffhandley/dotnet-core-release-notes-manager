#!/usr/bin/env bash
# api-diff-producer-preload.sh
#
# Host-side preload for the API Diff Producer. Given a single discovery target it
# generates (or refreshes) the milestone's API diff reports into the working tree
# and writes the agent context. The heavy/networked work happens here (pwsh +
# feed access on the runner host) so the agent only stages, narrates, and handles
# feedback.
#
# Reports land in:  release-notes/<major>/preview/<milestone>/api-diff/
# Attribute overlay: release-notes/<major>/preview/<milestone>/api-diff/_attributes-exclude.txt
#   -- a committed, milestone-scoped list of extra attributes to exclude. The
#   agent appends to it when write-access reviewers ask to drop low-value
#   attribute noise; this preload merges it into the diff's exclusions so future
#   refreshes stay clean.
#
# Generation modes:
#   - live (default): RunApiDiff.ps1 -CurrentMajorMinor <mm> -CurrentPrereleaseLabel
#     <label> -InstallApiDiff. Best-effort + time-bounded: an in-development
#     milestone's ref packs may not be published yet, so a failure is recorded as
#     a "pending" status rather than aborting the run.
#   - simulate (SIMULATE_API_DIFF_FROM=<milestone>): copy an existing in-repo
#     api-diff folder as the generated content, re-prefixing the version. Lets the
#     lifecycle be exercised deterministically without live feed availability.
#
# Inputs:
#   TARGET      required  single discovery target (JSON) from api-diff-discover.sh
#   AGENT_DIR   optional  where to write target.json (default /tmp/gh-aw/agent)
#   CONTENT_ROOT optional release-notes content root (default release-notes)
# Environment:
#   API_DIFF_TIMEOUT          optional  seconds for the live diff (default 1500)
#   SIMULATE_API_DIFF_FROM    optional  source milestone folder for simulation
#   GH_TOKEN                  optional  used to resolve the VMR head SHA
#   VMR_REPO                  optional  VMR repo (default dotnet/dotnet)
set -euo pipefail

TARGET="${TARGET:?TARGET (discovery JSON) is required}"
AGENT_DIR="${AGENT_DIR:-/tmp/gh-aw/agent}"
CONTENT_ROOT="${CONTENT_ROOT:-release-notes}"
VMR_REPO="${VMR_REPO:-dotnet/dotnet}"
mkdir -p "$AGENT_DIR"

major="$(jq -r '.major' <<<"$TARGET")"
milestone="$(jq -r '.milestone' <<<"$TARGET")"
dotted="$(jq -r '.milestone_dotted' <<<"$TARGET")"
vmr_ref="$(jq -r '.vmr_ref' <<<"$TARGET")"
base_branch="$(jq -r '.base_branch' <<<"$TARGET")"

content_dir="${CONTENT_ROOT}/${major}/preview/${milestone}/api-diff"
overlay="${content_dir}/_attributes-exclude.txt"
label_arg=()
case "$dotted" in
ga | "") : ;; # GA: omit the prerelease label
*) label_arg=(-CurrentPrereleaseLabel "$dotted") ;;
esac

# ---- 1. Seed any committed branch state (existing reports + overlay) --------
if git fetch --no-tags --depth=1 origin "$base_branch" >/dev/null 2>&1; then
	echo "::notice::seeding working tree from existing ${base_branch}"
	git checkout -q "origin/${base_branch}" -- "$content_dir" 2>/dev/null || true
fi
mkdir -p "$content_dir"
[ -f "$overlay" ] || : >"$overlay"

# ---- 2. Build the merged attribute-exclusion file --------------------------
merged_excludes="$(mktemp)"
default_excludes="${CONTENT_ROOT}/ApiDiffAttributesToExclude.txt"
[ -f "$default_excludes" ] && cat "$default_excludes" >"$merged_excludes"
if [ -s "$overlay" ]; then
	echo "::notice::applying $(grep -cvE '^\s*(#|$)' "$overlay" || echo 0) attribute overlay entry(ies) from ${overlay}"
	grep -vE '^\s*(#|$)' "$overlay" >>"$merged_excludes" || true
fi

# ---- 3. Generate the reports -----------------------------------------------
generated=0
if [ -n "${SIMULATE_API_DIFF_FROM:-}" ]; then
	src="${CONTENT_ROOT}/${major}/preview/${SIMULATE_API_DIFF_FROM}/api-diff"
	echo "::group::simulate api-diff for ${major} ${dotted} from ${SIMULATE_API_DIFF_FROM}"
	if [ -d "$src" ]; then
		rm -rf "$content_dir"
		mkdir -p "$content_dir"
		cp -R "$src/." "$content_dir/"
		# Re-prefix version-stamped TOC/report filenames and their contents.
		from="${major}-${SIMULATE_API_DIFF_FROM}"
		to="${major}-${milestone}"
		find "$content_dir" -type f -name "*${from}*" | while IFS= read -r f; do
			mv "$f" "${f/${from}/${to}}"
		done
		grep -rlF "$from" "$content_dir" 2>/dev/null | while IFS= read -r f; do
			sed -i.bak "s/${from}/${to}/g" "$f" && rm -f "$f.bak"
		done
		# Honor the attribute overlay by pruning matching lines from the reports.
		if [ -s "$overlay" ]; then
			while IFS= read -r attr; do
				[ -n "$attr" ] || continue
				case "$attr" in \#*) continue ;; esac
				find "$content_dir" -type f -name "*.md" -exec sed -i.bak "/$(printf '%s' "$attr" | sed 's/[.[\*^$/]/\\&/g')/d" {} \; -exec rm -f {}.bak \;
			done <"$overlay"
		fi
		generated=1
		echo "simulated api-diff staged under ${content_dir}"
	else
		echo "::warning::SIMULATE_API_DIFF_FROM source not found: ${src}"
	fi
	echo "::endgroup::"
elif command -v pwsh >/dev/null 2>&1 && [ -f "${CONTENT_ROOT}/RunApiDiff.ps1" ]; then
	echo "::group::api-diff ${major} ${dotted} (live, best-effort)"
	if timeout "${API_DIFF_TIMEOUT:-1500}" pwsh "${CONTENT_ROOT}/RunApiDiff.ps1" \
		-CurrentMajorMinor "$major" "${label_arg[@]}" \
		-AttributesToExcludeFilePath "$merged_excludes" \
		-CoreRepo "$(pwd)" -InstallApiDiff; then
		generated=1
		echo "api-diff generated under ${content_dir}"
	else
		echo "::warning::api-diff generation failed or timed out (best-effort) -- the milestone's ref packs are likely not published on the feed yet; the PR will record a pending status."
	fi
	echo "::endgroup::"
else
	echo "::notice::pwsh or ${CONTENT_ROOT}/RunApiDiff.ps1 unavailable; skipping generation."
fi

# Keep the overlay present in the generated tree so it persists on the branch.
[ -f "$overlay" ] || : >"$overlay"

# ---- 4. Resolve the VMR head SHA for provenance ----------------------------
vmr_sha=""
if [ -n "${GH_TOKEN:-}" ]; then
	vmr_sha="$(gh api "repos/${VMR_REPO}/commits/${vmr_ref}" -q '.sha' 2>/dev/null | head -c 40 || true)"
fi

# ---- 5. Report presence + agent target.json --------------------------------
report_count="$(find "$content_dir" -type f -name "*.md" ! -name "README.md" 2>/dev/null | wc -l | tr -d ' ')"
jq -n \
	--argjson target "$TARGET" \
	--arg content_dir "$content_dir" \
	--arg overlay "$overlay" \
	--arg vmr_sha "$vmr_sha" \
	--argjson generated "$generated" \
	--argjson report_count "$report_count" \
	--arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	'$target + {
     content_dir: $content_dir,
     overlay_path: $overlay,
     vmr_sha: $vmr_sha,
     generated: ($generated == 1),
     report_count: $report_count,
     generated_at: $generated_at
   }' >"$AGENT_DIR/target.json"

rm -f "$merged_excludes"
echo "=== target.json ==="
jq '.' "$AGENT_DIR/target.json"
echo "reports present: ${report_count}"
