#!/usr/bin/env bash
# api-diff-producer-preload.sh
#
# Host-side preload for the API Diff Producer. Given a single discovery target it
# generates the milestone's API diff reports from REAL published builds and writes
# the agent context. Heavy/networked work happens here (pwsh + feed access) so the
# agent only stages, narrates, and routes feedback.
#
# NO SIMULATION. Ref packs come from the feeds the target pins (current from the
# dotnet{major} channel feed; previous-major GA from dotnet-public). The ApiDiff
# TOOL installs from dotnet{major}-transport; ref packs are never consumed from
# the -transport feed.
#
# Exclusions (apidiff file format: attributes "T:<FullTypeName>" per line;
# assemblies bare name per line):
#   - permanent attributes : release-notes/ApiDiffAttributesToExclude.txt
#   - temporary attributes : <content_dir>/ApiDiffAttributesToExclude.txt (per report)
#   - permanent assemblies : release-notes/ApiDiffAssembliesToExclude.txt (no temporary)
# The permanent + temporary attribute lists are merged into one file passed to the
# tool (the CLI takes a single -eattrs file); the global assemblies file is passed
# as -eas. Pending permanent edits on the PR branch are honored before merge.
#
# Output:
#   incremental     -> release-notes/<mm>/preview/<milestone>/api-diff
#   major-to-major  -> release-notes/<mm>/<mm>.0/api-diff (relocated from the tool's
#                      preview folder when the current endpoint is a prerelease)
#
# HARD no-build gate: no reports produced -> produce=false -> the producer opens no
# PR. FAST no-op: an existing PR whose recorded current_version is unchanged and
# that has no unprocessed (un-:eyes:'d) write-access feedback skips generation
# entirely (noop=true) so the typical scheduled run does nothing.
#
# Inputs:
#   TARGET      required  single discovery target (JSON) from api-diff-discover.sh
#   AGENT_DIR   optional  where to write target.json (default /tmp/gh-aw/agent)
#   CONTENT_ROOT optional release-notes content root (default release-notes)
# Environment:
#   API_DIFF_TIMEOUT  optional  seconds for the diff (default 1800)
#   GH_TOKEN          optional  PR lookup + VMR SHA
#   GH_RUN_ID         optional  workflow run id for the branch collision suffix
#   GITHUB_REPOSITORY optional  owner/repo for PR/comment lookups
set -euo pipefail

TARGET="${TARGET:?TARGET (discovery JSON) is required}"
AGENT_DIR="${AGENT_DIR:-/tmp/gh-aw/agent}"
CONTENT_ROOT="${CONTENT_ROOT:-release-notes}"
REPO="${GITHUB_REPOSITORY:-}"
mkdir -p "$AGENT_DIR"

jqr() { jq -r "$1" <<<"$TARGET"; }
track="$(jqr '.track')"
major="$(jqr '.major')"
prev_vm="$(jqr '.prev_vm')"
cur_vm="$(jqr '.cur_vm')"
previous_version="$(jqr '.previous_version')"
previous_feed="$(jqr '.previous_feed')"
current_version="$(jqr '.current_version')"
current_feed="$(jqr '.current_feed')"
content_dir="$(jqr '.content_dir')"
cur_milestone="$(jqr '.cur_milestone')"
desired_branch="$(jqr '.desired_branch')"
vmr_ref="$(jqr '.vmr_ref')"
status="$(jqr '.status')"

marker="<!-- api-diff:${prev_vm}_to_${cur_vm} -->"
perm_attrs="${CONTENT_ROOT}/ApiDiffAttributesToExclude.txt"
perm_asms="${CONTENT_ROOT}/ApiDiffAssembliesToExclude.txt"
temp_attrs="${content_dir}/ApiDiffAttributesToExclude.txt"

# human_vm <version-milestone> -> ".NET 11 Preview 6" / ".NET 10" / ".NET 11 RC 1"
human_vm() {
	local vm="$1" maj ms
	maj="${vm%%-*}"
	maj="${maj%.*}"
	ms="${vm#*-}"
	case "$ms" in
	ga) echo ".NET ${maj}" ;;
	preview.*) echo ".NET ${maj} Preview ${ms#preview.}" ;;
	rc.*) echo ".NET ${maj} RC ${ms#rc.}" ;;
	*) echo ".NET ${maj} ${ms}" ;;
	esac
}
prev_human="$(human_vm "$prev_vm")"
cur_human="$(human_vm "$cur_vm")"
if [ "$track" = "major-to-major" ]; then
	pr_title="API diff between .NET ${prev_vm%%.*} and .NET ${major%.*}"
else
	pr_title="API diff between ${prev_human} and ${cur_human}"
fi

# ---- 0. Resolve the existing marker PR + target branch ---------------------
existing_pr_number=""
target_branch="$desired_branch"
if [ -n "${GH_TOKEN:-}" ]; then
	prs_json="$(gh pr list --state open --limit 100 --json number,headRefName,body 2>/dev/null || echo '[]')"
	match="$(jq -c --arg m "$marker" 'map(select(.body | contains($m))) | .[0] // empty' <<<"$prs_json")"
	if [ -n "$match" ]; then
		existing_pr_number="$(jq -r '.number' <<<"$match")"
		target_branch="$(jq -r '.headRefName' <<<"$match")"
		echo "::notice::reusing marker PR #${existing_pr_number} on ${target_branch}"
	elif git ls-remote --exit-code --heads origin "$desired_branch" >/dev/null 2>&1; then
		target_branch="${desired_branch}_${GH_RUN_ID:-$(date +%s)}"
		echo "::notice::${desired_branch} already exists; using collision branch ${target_branch}"
	fi
fi

# unprocessed_feedback <pr> -> count of write-access comments lacking an :eyes: marker
unprocessed_feedback() {
	local pr="$1" n=0 id assoc type rx
	if [ -z "$REPO" ] || [ -z "${GH_TOKEN:-}" ]; then
		echo 0
		return
	fi
	for kind in "issues/${pr}/comments|issues" "pulls/${pr}/comments|pulls"; do
		local path="${kind%|*}" base="${kind#*|}"
		while IFS=$'\t' read -r id assoc type; do
			[ -n "$id" ] || continue
			case "$assoc" in OWNER | MEMBER | COLLABORATOR) ;; *) continue ;; esac
			[ "$type" = "Bot" ] && continue
			rx="$(gh api "repos/${REPO}/${base}/comments/${id}/reactions" -q '.[].content' 2>/dev/null || true)"
			grep -q eyes <<<"$rx" || n=$((n + 1))
		done < <(gh api "repos/${REPO}/${path}" --paginate -q '.[]|"\(.id)\t\(.author_association)\t\(.user.type)"' 2>/dev/null || true)
	done
	echo "$n"
}

# ---- 1. Fast no-op: unchanged build + no unprocessed feedback ---------------
noop=false
if [ -n "$existing_pr_number" ]; then
	recorded="$(gh pr view "$existing_pr_number" --json body -q '.body' 2>/dev/null | sed -n 's/^[[:space:]]*current_version: "\(.*\)"$/\1/p' | head -1)"
	pending="$(unprocessed_feedback "$existing_pr_number")"
	if [ "$recorded" = "$current_version" ] && [ "$pending" -eq 0 ]; then
		noop=true
		echo "::notice::no-op: ${cur_vm} build unchanged (${current_version}) and no unprocessed feedback; skipping generation"
	fi
fi

# ---- 2. Seed branch state (reports + per-report + pending permanent edits) --
if [ "$noop" = false ] && [ -n "${GH_TOKEN:-}" ] && git fetch --no-tags --depth=1 origin "$target_branch" >/dev/null 2>&1; then
	echo "::notice::seeding working tree from ${target_branch}"
	git checkout -q "origin/${target_branch}" -- "$content_dir" 2>/dev/null || true
	git checkout -q "origin/${target_branch}" -- "$perm_attrs" "$perm_asms" 2>/dev/null || true
fi
mkdir -p "$content_dir"
[ -f "$temp_attrs" ] || : >"$temp_attrs"
temp_keep="$(mktemp)"
cp "$temp_attrs" "$temp_keep"

# ---- 3. Generate (unless no-op) --------------------------------------------
if [ "$track" = "major-to-major" ] && [ "$cur_milestone" != "ga" ]; then
	tool_output_dir="${CONTENT_ROOT}/${major}/preview/${cur_milestone}/api-diff"
else
	tool_output_dir="$content_dir"
fi

if [ "$noop" = false ]; then
	merged_attrs="$(mktemp)"
	[ -f "$perm_attrs" ] && cat "$perm_attrs" >>"$merged_attrs"
	if [ -s "$temp_attrs" ]; then
		grep -vE '^[[:space:]]*(#|$)' "$temp_attrs" >>"$merged_attrs" 2>/dev/null || true
	fi
	# de-duplicate
	sort -u "$merged_attrs" -o "$merged_attrs"

	# RunApiDiff.ps1 resolves a non-rooted exclude-file path relative to its own
	# script dir (release-notes/), so a repo-relative path like
	# release-notes/ApiDiffAssembliesToExclude.txt would double to
	# release-notes/release-notes/... -- pass absolute paths.
	abs_asms="$perm_asms"
	case "$abs_asms" in /*) ;; *) abs_asms="$(pwd)/$abs_asms" ;; esac

	if command -v pwsh >/dev/null 2>&1 && [ -f "${CONTENT_ROOT}/RunApiDiff.ps1" ]; then
		echo "::group::api-diff ${track}: ${previous_version} -> ${current_version}"
		TIMEOUT=()
		command -v timeout >/dev/null && TIMEOUT=(timeout "${API_DIFF_TIMEOUT:-1800}")
		ASMS_ARG=()
		[ -f "$abs_asms" ] && ASMS_ARG=(-AssembliesToExcludeFilePath "$abs_asms")
		"${TIMEOUT[@]}" pwsh "${CONTENT_ROOT}/RunApiDiff.ps1" \
			-PreviousVersion "$previous_version" -PreviousNuGetFeed "$previous_feed" \
			-CurrentVersion "$current_version" -CurrentNuGetFeed "$current_feed" \
			-AttributesToExcludeFilePath "$merged_attrs" \
			"${ASMS_ARG[@]}" \
			-CoreRepo "$(pwd)" -InstallApiDiff || echo "::warning::RunApiDiff exited non-zero; checking for produced reports"
		echo "::endgroup::"
	else
		echo "::warning::pwsh or ${CONTENT_ROOT}/RunApiDiff.ps1 unavailable; cannot generate."
	fi
	rm -f "$merged_attrs"
fi

# ---- 3b. Gate on produced reports + relocate major-to-major output ----------
produced=0
if [ "$noop" = false ]; then
	produced="$(find "$tool_output_dir" -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
	if [ "$produced" -gt 0 ] && [ "$track" = "major-to-major" ] && [ "$tool_output_dir" != "$content_dir" ]; then
		echo "::notice::relocating major-to-major output ${tool_output_dir} -> ${content_dir}"
		rm -rf "$content_dir"
		mkdir -p "$(dirname "$content_dir")"
		mv "$tool_output_dir" "$content_dir"
		rmdir "${CONTENT_ROOT}/${major}/preview/${cur_milestone}" 2>/dev/null || true
	fi
	[ "$produced" -gt 0 ] || echo "::warning::no reports produced (no build / no API changes); no PR will be opened."
fi

# Restore the durable per-report temporary list so it persists on the branch.
cp "$temp_keep" "$temp_attrs"

# ---- 4. VMR head SHA for provenance ----------------------------------------
vmr_sha=""
if [ -n "${GH_TOKEN:-}" ]; then
	vmr_sha="$(gh api "repos/dotnet/dotnet/commits/${vmr_ref}" -q '.sha' 2>/dev/null | head -c 40 || true)"
fi

# ---- 5. Agent target.json --------------------------------------------------
report_count="$(find "$content_dir" -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$noop" = true ] || [ "$report_count" -eq 0 ]; then produce=false; else produce=true; fi
temp_excluded="$(jq -R . "$temp_attrs" 2>/dev/null | jq -cs 'map(select(test("^[[:space:]]*(#|$)") | not))' 2>/dev/null || echo '[]')"
[ -n "$temp_excluded" ] || temp_excluded='[]'

if [ "$status" = "code-complete" ]; then
	status_note="**Ready for Review** — ${cur_human} has snapped to a release branch (code complete)."
else
	status_note="**Draft** — auto-maintained until ${cur_human} snaps to a release branch."
fi
if [ "$track" = "major-to-major" ]; then
	tldr="Cumulative public API diff **.NET ${prev_vm%%.*} → .NET ${major%.*}**, currently reflecting ${cur_human}. Refreshes as .NET ${major%.*} advances toward release."
else
	tldr="Incremental public API diff **${prev_human} → ${cur_human}**."
fi

jq -n \
	--argjson target "$TARGET" \
	--arg content_dir "$content_dir" \
	--arg perm_attrs "$perm_attrs" \
	--arg perm_asms "$perm_asms" \
	--arg temp_attrs "$temp_attrs" \
	--arg marker "$marker" \
	--arg pr_title "$pr_title" \
	--arg tldr "$tldr" \
	--arg status_note "$status_note" \
	--arg target_branch "$target_branch" \
	--arg existing_pr_number "$existing_pr_number" \
	--arg vmr_sha "$vmr_sha" \
	--argjson produce "$produce" \
	--argjson noop "$noop" \
	--argjson report_count "$report_count" \
	--argjson temp_excluded_attributes "$temp_excluded" \
	--arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	'$target + {
     content_dir: $content_dir,
     permanent_attributes_file: $perm_attrs,
     permanent_assemblies_file: $perm_asms,
     temporary_attributes_file: $temp_attrs,
     marker: $marker,
     pr_title: $pr_title,
     tldr: $tldr,
     status_note: $status_note,
     target_branch: $target_branch,
     existing_pr_number: $existing_pr_number,
     vmr_sha: $vmr_sha,
     produce: $produce,
     noop: $noop,
     report_count: $report_count,
     temp_excluded_attributes: $temp_excluded_attributes,
     generated_at: $generated_at
   }' >"$AGENT_DIR/target.json"

rm -f "$temp_keep"
echo "=== target.json ==="
jq '.' "$AGENT_DIR/target.json"
echo "noop=${noop} produce=${produce} reports=${report_count} branch=${target_branch}"
