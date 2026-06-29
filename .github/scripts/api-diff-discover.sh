#!/usr/bin/env bash
# api-diff-discover.sh
#
# Deterministic discovery for the API Diff Manager, driven by the dotnet/dotnet
# VMR. Emits the set of active, not-yet-shipped release milestones that should
# have an API diff report generated:
#
#   - IN-DEVELOPMENT: the milestone currently on the VMR `main` branch, read from
#     eng/Versions.props (VersionMajor/Minor + PreReleaseVersionLabel/Iteration).
#     Its API diff PR stays a DRAFT.
#   - CODE-COMPLETE: every milestone that has snapped into a VMR release branch
#     named `release/<major>.<minor>.<sdk>xx-<preview|rc><n>`. The snap means code
#     complete, so its API diff PR is marked Ready for Review.
#
# Plain GA servicing bands (`release/<major>.<minor>.<sdk>xx` with no -preview/-rc
# suffix) are already-shipped majors and are excluded.
#
# The previous milestone to diff against is intentionally NOT computed here:
# RunApiDiff.ps1 infers it from the existing api-diff folders in the repo.
#
# Requires `gh` (GH_TOKEN) and `jq`. Emits a JSON array to stdout.
#
# Environment:
#   VMR_REPO    optional  VMR repo (default dotnet/dotnet)
set -euo pipefail

VMR_REPO="${VMR_REPO:-dotnet/dotnet}"

# props_field <ref> <xml-element> -> text content of the first matching element
props_field() {
	local ref="$1" field="$2"
	gh api "repos/${VMR_REPO}/contents/eng/Versions.props?ref=${ref}" \
		-q '.content' 2>/dev/null | base64 -d 2>/dev/null |
		grep -oE "<${field}>[^<]*</${field}>" | head -1 |
		sed -E "s#</?${field}>##g"
}

targets="[]"

# add_target <major> <milestone-folder> <milestone-dotted> <vmr-ref> <status>
add_target() {
	targets="$(jq -c \
		--arg major "$1" --arg milestone "$2" --arg dotted "$3" \
		--arg ref "$4" --arg status "$5" \
		--arg base "api-diff/$1-$3" \
		'. += [{major: $major, milestone: $milestone, milestone_dotted: $dotted,
              vmr_ref: $ref, status: $status, base_branch: $base}]' <<<"$targets")"
}

# ---- 1. IN-DEVELOPMENT milestone on main -----------------------------------
major="$(props_field main VersionMajor)"
minor="$(props_field main VersionMinor)"
label="$(props_field main PreReleaseVersionLabel)"
iter="$(props_field main PreReleaseVersionIteration)"
if [ -n "$major" ] && [ -n "$minor" ] && [ -n "$label" ] && [ -n "$iter" ]; then
	add_target "${major}.${minor}" "${label}${iter}" "${label}.${iter}" main "in-development"
	echo "::notice::main is ${major}.${minor} ${label}.${iter} (in-development)" >&2
else
	echo "::warning::could not resolve the in-development milestone from ${VMR_REPO}@main" >&2
fi

# ---- 2. CODE-COMPLETE milestones in release/* snaps ------------------------
# Branch shape: release/<major>.<minor>.<sdk>xx-<preview|rc><n> (e.g. release/11.0.1xx-preview6)
while IFS= read -r branch; do
	[ -n "$branch" ] || continue
	if [[ "$branch" =~ ^release/([0-9]+)\.([0-9]+)\.[0-9]+xx-(preview|rc)([0-9]+)$ ]]; then
		bmajor="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
		blabel="${BASH_REMATCH[3]}"
		bnum="${BASH_REMATCH[4]}"
		# Skip if this (major, milestone) is already represented (e.g. also main).
		if jq -e --arg m "$bmajor" --arg ms "${blabel}${bnum}" \
			'any(.[]; .major == $m and .milestone == $ms)' <<<"$targets" >/dev/null; then
			continue
		fi
		add_target "$bmajor" "${blabel}${bnum}" "${blabel}.${bnum}" "$branch" "code-complete"
		echo "::notice::${branch} -> ${bmajor} ${blabel}.${bnum} (code-complete)" >&2
	fi
done < <(gh api "repos/${VMR_REPO}/branches" --paginate -q '.[].name' 2>/dev/null | grep -E '^release/' || true)

jq -c 'unique_by([.major, .milestone]) | sort_by(.major, .milestone)' <<<"$targets"
