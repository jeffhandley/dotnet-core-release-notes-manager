#!/usr/bin/env bash
# api-diff-producer-preload.sh
#
# Host-side preload for the API Diff Producer. Given a single discovery target it
# generates the milestone's API diff reports from REAL published builds and writes
# the agent context. Heavy/networked work happens here (pwsh + feed access) so the
# agent only stages, narrates, and handles feedback.
#
# NO SIMULATION. Ref packs are downloaded from the exact feeds the target pins:
#   - current build  : the per-major channel feed dotnet{major} (pre-release builds)
#   - previous build : dotnet-public GA baseline (or dotnet{prev} if not GA yet)
# The ApiDiff TOOL installs from dotnet{major}-transport (-InstallApiDiff); ref packs
# are never consumed from the -transport feed.
#
# Output:
#   incremental     -> release-notes/<mm>/preview/<milestone>/api-diff
#   major-to-major  -> release-notes/<mm>/<mm>.0/api-diff (relocated from the tool's
#                      preview folder when the current endpoint is a prerelease)
# Attribute overlay: <content_dir>/_attributes-exclude.txt (durable, milestone-scoped).
#
# HARD no-build gate: if no reports are produced, target.json sets produce=false and
# the producer opens NO PR (existing PRs are left untouched).
#
# Branch/PR are resolved deterministically here (endpoint marker + collision suffix):
#   marker        = <!-- api-diff:<prev_vm>_to_<cur_vm> -->
#   target_branch = the open marker-PR's head, else api-diff/<prev_vm>_to_<cur_vm>,
#                   else (that branch already exists) api-diff/<...>_<run_id>
#
# Inputs:
#   TARGET      required  single discovery target (JSON) from api-diff-discover.sh
#   AGENT_DIR   optional  where to write target.json (default /tmp/gh-aw/agent)
#   CONTENT_ROOT optional release-notes content root (default release-notes)
# Environment:
#   API_DIFF_TIMEOUT  optional  seconds for the diff (default 1800)
#   GH_TOKEN          optional  PR lookup + VMR SHA
#   GH_RUN_ID         optional  workflow run id for the branch collision suffix
set -euo pipefail

TARGET="${TARGET:?TARGET (discovery JSON) is required}"
AGENT_DIR="${AGENT_DIR:-/tmp/gh-aw/agent}"
CONTENT_ROOT="${CONTENT_ROOT:-release-notes}"
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

overlay="${content_dir}/_attributes-exclude.txt"
marker="<!-- api-diff:${prev_vm}_to_${cur_vm} -->"

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

# ---- 1. Seed existing reports + overlay from the target branch -------------
if [ -n "${GH_TOKEN:-}" ] && git fetch --no-tags --depth=1 origin "$target_branch" >/dev/null 2>&1; then
	echo "::notice::seeding working tree from ${target_branch}"
	git checkout -q "origin/${target_branch}" -- "$content_dir" 2>/dev/null || true
fi
mkdir -p "$content_dir"
[ -f "$overlay" ] || : >"$overlay"
overlay_keep="$(mktemp)"
cp "$overlay" "$overlay_keep"

# ---- 2. Build the merged attribute-exclusion file --------------------------
merged_excludes="$(mktemp)"
default_excludes="${CONTENT_ROOT}/ApiDiffAttributesToExclude.txt"
[ -f "$default_excludes" ] && cat "$default_excludes" >"$merged_excludes"
overlay_entries="$(grep -vE '^[[:space:]]*(#|$)' "$overlay_keep" 2>/dev/null || true)"
if [ -n "$overlay_entries" ]; then
	echo "::notice::applying $(printf '%s\n' "$overlay_entries" | grep -c .) attribute overlay entry(ies)"
	printf '%s\n' "$overlay_entries" >>"$merged_excludes"
fi

# ---- 3. Generate the reports from real builds ------------------------------
# Determine where the tool writes: a prerelease current routes to the preview
# folder (IsComparingReleases is only true for GA->GA), so major-to-major gets
# relocated into <mm>/<mm>.0 afterward.
if [ "$track" = "major-to-major" ] && [ "$cur_milestone" != "ga" ]; then
	tool_output_dir="${CONTENT_ROOT}/${major}/preview/${cur_milestone}/api-diff"
else
	tool_output_dir="$content_dir"
fi

if command -v pwsh >/dev/null 2>&1 && [ -f "${CONTENT_ROOT}/RunApiDiff.ps1" ]; then
	echo "::group::api-diff ${track}: ${previous_version} -> ${current_version}"
	TIMEOUT=()
	command -v timeout >/dev/null && TIMEOUT=(timeout "${API_DIFF_TIMEOUT:-1800}")
	# Don't gate on the exit code alone -- the tool can emit a non-zero on a
	# benign archive/cleanup warning after writing valid reports. Gate on whether
	# reports were actually produced.
	"${TIMEOUT[@]}" pwsh "${CONTENT_ROOT}/RunApiDiff.ps1" \
		-PreviousVersion "$previous_version" -PreviousNuGetFeed "$previous_feed" \
		-CurrentVersion "$current_version" -CurrentNuGetFeed "$current_feed" \
		-AttributesToExcludeFilePath "$merged_excludes" \
		-CoreRepo "$(pwd)" -InstallApiDiff || echo "::warning::RunApiDiff exited non-zero; checking for produced reports"
	echo "::endgroup::"
else
	echo "::warning::pwsh or ${CONTENT_ROOT}/RunApiDiff.ps1 unavailable; cannot generate."
fi

# ---- 3b. Gate on produced reports + relocate major-to-major output ----------
produced="$(find "$tool_output_dir" -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$produced" -gt 0 ]; then
	if [ "$track" = "major-to-major" ] && [ "$tool_output_dir" != "$content_dir" ]; then
		echo "::notice::relocating major-to-major output ${tool_output_dir} -> ${content_dir}"
		rm -rf "$content_dir"
		mkdir -p "$(dirname "$content_dir")"
		mv "$tool_output_dir" "$content_dir"
		rmdir "${CONTENT_ROOT}/${major}/preview/${cur_milestone}" 2>/dev/null || true
	fi
else
	echo "::warning::no reports produced (no build available or generation failed); no PR will be opened."
fi

# Restore the durable overlay so it persists on the branch.
cp "$overlay_keep" "$overlay"

# ---- 4. VMR head SHA for provenance ----------------------------------------
vmr_sha=""
if [ -n "${GH_TOKEN:-}" ]; then
	vmr_sha="$(gh api "repos/dotnet/dotnet/commits/${vmr_ref}" -q '.sha' 2>/dev/null | head -c 40 || true)"
fi

# ---- 5. Agent target.json --------------------------------------------------
report_count="$(find "$content_dir" -type f -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$report_count" -gt 0 ] && produce=true || produce=false
excluded_attributes="$(jq -R . "$overlay" 2>/dev/null | jq -cs 'map(select(test("^[[:space:]]*(#|$)") | not))' 2>/dev/null || echo '[]')"
[ -n "$excluded_attributes" ] || excluded_attributes='[]'

jq -n \
	--argjson target "$TARGET" \
	--arg content_dir "$content_dir" \
	--arg overlay "$overlay" \
	--arg marker "$marker" \
	--arg target_branch "$target_branch" \
	--arg existing_pr_number "$existing_pr_number" \
	--arg vmr_sha "$vmr_sha" \
	--argjson produce "$produce" \
	--argjson report_count "$report_count" \
	--argjson excluded_attributes "$excluded_attributes" \
	--arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	'$target + {
     content_dir: $content_dir,
     overlay_path: $overlay,
     marker: $marker,
     target_branch: $target_branch,
     existing_pr_number: $existing_pr_number,
     vmr_sha: $vmr_sha,
     produce: $produce,
     report_count: $report_count,
     excluded_attributes: $excluded_attributes,
     generated_at: $generated_at
   }' >"$AGENT_DIR/target.json"

rm -f "$merged_excludes" "$overlay_keep"
echo "=== target.json ==="
jq '.' "$AGENT_DIR/target.json"
echo "produce=${produce} reports=${report_count} branch=${target_branch}"
