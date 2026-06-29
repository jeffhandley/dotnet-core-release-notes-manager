#!/usr/bin/env bash
# api-diff-discover.sh
#
# Deterministic discovery for the API Diff Manager, driven by the dotnet/dotnet
# VMR plus the dnceng NuGet feeds. Emits the set of API diff reports to produce
# for the active, not-yet-shipped majors. Two tracks per active major:
#
#   - major-to-major (cumulative): (X-1) GA -> X head. Content under
#     release-notes/<mm>/<mm>.0/api-diff.
#   - incremental (frontier): previous milestone -> X head milestone. Content under
#     release-notes/<mm>/preview/<milestone>/api-diff.
#
# Ref packs are consumed from the per-major channel feed dotnet{major} (it carries
# the latest in-development prerelease builds, so diffs are produced BEFORE public
# release). The previous-major GA baseline comes from dotnet-public. A target is
# emitted ONLY when its current build actually exists on the feed -- no build, no
# target, no PR. The -transport feed is never used to consume ref packs.
#
# Each target pins the exact previous/current package versions and the feed each
# is downloaded from, so the producer never has to guess.
#
# Requires `gh` (GH_TOKEN), `jq`, `curl`. Emits a JSON array to stdout.
#
# Environment:
#   VMR_REPO    optional  VMR repo (default dotnet/dotnet)
set -euo pipefail

VMR_REPO="${VMR_REPO:-dotnet/dotnet}"
PUBLIC_CHANNEL="dotnet-public"

feed_index() { # <channel> -> v3 index.json URL
	echo "https://pkgs.dev.azure.com/dnceng/public/_packaging/$1/nuget/v3/index.json"
}

# versions_on <channel> -> Microsoft.NETCore.App.Ref versions (cached)
declare -A _VERS_CACHE
versions_on() {
	local channel="$1"
	if [ -z "${_VERS_CACHE[$channel]:-}" ]; then
		local url="https://pkgs.dev.azure.com/dnceng/public/_packaging/${channel}/nuget/v3/flat2/microsoft.netcore.app.ref/index.json"
		_VERS_CACHE[$channel]="$(curl -fsSL "$url" 2>/dev/null | jq -r '.versions[]?' 2>/dev/null || true)"
		[ -n "${_VERS_CACHE[$channel]}" ] || _VERS_CACHE[$channel]="__none__"
	fi
	[ "${_VERS_CACHE[$channel]}" = "__none__" ] || printf '%s\n' "${_VERS_CACHE[$channel]}"
}

# latest_build <channel> <mm> <label-dotted|ga> -> newest matching version (or empty)
latest_build() {
	local channel="$1" mm="$2" label="$3" pat
	if [ "$label" = "ga" ] || [ -z "$label" ]; then
		pat="^${mm//./\\.}\\.0\$"
	else
		pat="^${mm//./\\.}\\.0-${label//./\\.}\\."
	fi
	versions_on "$channel" | grep -E "$pat" | sort -V | tail -1
}

# max_milestone_number <channel> <mm> <kind> -> highest N for <mm>.0-<kind>.N.* (or empty)
max_milestone_number() {
	local channel="$1" mm="$2" kind="$3"
	versions_on "$channel" | grep -oE "^${mm//./\\.}\\.0-${kind}\\.[0-9]+" |
		sed -E "s/.*-${kind}\\.//" | sort -n | tail -1
}

props_field() { # <ref> <element>
	local ref="$1" el="$2" raw=""
	# Reading eng/Versions.props must always succeed; an empty result is a
	# transient API failure, never a legitimate value, so retry before giving up.
	for _ in 1 2 3; do
		raw="$(gh api "repos/${VMR_REPO}/contents/eng/Versions.props?ref=${ref}" -q '.content' 2>/dev/null | base64 -d 2>/dev/null || true)"
		[ -n "$raw" ] && break
		sleep 2
	done
	grep -oE "<$el>[^<]*</$el>" <<<"$raw" | head -1 | sed -E "s#</?$el>##g"
}

targets="[]"
emit() { targets="$(jq -c --argjson t "$1" '. += [$t]' <<<"$targets")"; }

# ---- VMR signals -----------------------------------------------------------
main_major="$(props_field main VersionMajor).$(props_field main VersionMinor)"
main_label="$(props_field main PreReleaseVersionLabel).$(props_field main PreReleaseVersionIteration)"
main_undotted="$(props_field main PreReleaseVersionLabel)$(props_field main PreReleaseVersionIteration)"
if ! [[ "$main_major" =~ ^[0-9]+\.[0-9]+$ ]]; then
	echo "::error::Could not resolve VMR main VersionMajor/VersionMinor from ${VMR_REPO} eng/Versions.props (got '${main_major}'). Aborting instead of emitting an empty target set." >&2
	exit 1
fi
echo "::notice::main = ${main_major} ${main_label}" >&2

# Map major -> highest snapped prerelease milestone (label-dotted) and its branch.
declare -A RB_LABEL RB_BRANCH RB_WEIGHT
while IFS= read -r branch; do
	[ -n "$branch" ] || continue
	if [[ "$branch" =~ ^release/([0-9]+\.[0-9]+)\.[0-9]+xx-(preview|rc)([0-9]+)$ ]]; then
		mm="${BASH_REMATCH[1]}"
		kind="${BASH_REMATCH[2]}"
		num="${BASH_REMATCH[3]}"
		w=$((num))
		[ "$kind" = rc ] && w=$((1000 + num))
		if [ -z "${RB_WEIGHT[$mm]:-}" ] || [ "$w" -gt "${RB_WEIGHT[$mm]}" ]; then
			RB_WEIGHT[$mm]=$w
			RB_LABEL[$mm]="${kind}.${num}"
			RB_BRANCH[$mm]="$branch"
		fi
	fi
done < <(gh api "repos/${VMR_REPO}/branches" --paginate -q '.[].name' 2>/dev/null | grep -E '^release/' || true)

# Active majors = main major + any major with a snapped prerelease release branch.
declare -A ACTIVE
ACTIVE[$main_major]=1
for mm in "${!RB_LABEL[@]}"; do ACTIVE[$mm]=1; done

# prev_milestone <mm> <head-label-dotted> <channel> -> "vm|version|feed" or empty
prev_milestone() {
	local mm="$1" head="$2" channel="$3" kind num plabel pver pfeed pmajor pmm m
	kind="${head%%.*}"
	num="${head##*.}"
	pmajor=$(($(echo "$mm" | cut -d. -f1) - 1))
	pmm="${pmajor}.0"
	if [ "$kind" = preview ] && [ "$num" -gt 1 ]; then
		plabel="preview.$((num - 1))"
	elif [ "$kind" = preview ]; then
		pver="$(latest_build "$PUBLIC_CHANNEL" "$pmm" ga)"
		[ -n "$pver" ] && echo "${pmm}-ga|${pver}|dotnet-public"
		return
	elif [ "$kind" = rc ] && [ "$num" -gt 1 ]; then
		plabel="rc.$((num - 1))"
	elif [ "$kind" = rc ]; then
		m="$(max_milestone_number "$channel" "$mm" preview)"
		[ -n "$m" ] && plabel="preview.${m}" || return
	else
		m="$(max_milestone_number "$channel" "$mm" rc)"
		[ -n "$m" ] && plabel="rc.${m}" || return
	fi
	pver="$(latest_build "$channel" "$mm" "$plabel")"
	pfeed="$channel"
	if [ -z "$pver" ]; then
		pver="$(latest_build "$PUBLIC_CHANNEL" "$mm" "$plabel")"
		pfeed="$PUBLIC_CHANNEL"
	fi
	[ -n "$pver" ] && echo "${mm}-${plabel}|${pver}|${pfeed}"
}

for X in "${!ACTIVE[@]}"; do
	major_int="$(echo "$X" | cut -d. -f1)"
	channel="dotnet${major_int}"

	if [ "$X" = "$main_major" ]; then
		head_label="$main_label"
		head_undotted="$main_undotted"
		vmr_ref="main"
		status="in-development"
	else
		head_label="${RB_LABEL[$X]:-}"
		head_undotted="${head_label/./}"
		vmr_ref="${RB_BRANCH[$X]:-}"
		status="code-complete"
		[ -n "$head_label" ] || continue
	fi

	cur_ver="$(latest_build "$channel" "$X" "$head_label")"
	cur_feed="$channel"
	if [ -z "$cur_ver" ]; then
		cur_ver="$(latest_build "$PUBLIC_CHANNEL" "$X" "$head_label")"
		cur_feed="$PUBLIC_CHANNEL"
	fi
	if [ -z "$cur_ver" ]; then
		echo "::notice::no build available for ${X} ${head_label}; skipping" >&2
		continue
	fi
	cur_vm="${X}-${head_label}"
	cur_feed_url="$(feed_index "$cur_feed")"
	echo "::notice::${X} head ${head_label} -> ${cur_ver} (${cur_feed})" >&2

	# ---- major-to-major: (X-1) GA -> X head ---------------------------------
	prev_major=$((major_int - 1))
	prev_mm="${prev_major}.0"
	prev_ga="${prev_mm}.0"
	if grep -qxF "$prev_ga" <<<"$(versions_on "$PUBLIC_CHANNEL")"; then
		mm_prev_ver="$prev_ga"
		mm_prev_feed="$PUBLIC_CHANNEL"
	else
		n="$(max_milestone_number "dotnet${prev_major}" "$prev_mm" rc)"
		if [ -n "$n" ]; then plabel="rc.$n"; else plabel="preview.$(max_milestone_number "dotnet${prev_major}" "$prev_mm" preview)"; fi
		mm_prev_ver="$(latest_build "dotnet${prev_major}" "$prev_mm" "$plabel")"
		mm_prev_feed="dotnet${prev_major}"
	fi
	if [ -n "$mm_prev_ver" ]; then
		emit "$(jq -cn \
			--arg track major-to-major --arg major "$X" \
			--arg prev_vm "${prev_mm}-ga" --arg cur_vm "$cur_vm" \
			--arg previous_version "$mm_prev_ver" --arg previous_feed "$(feed_index "$mm_prev_feed")" \
			--arg current_version "$cur_ver" --arg current_feed "$cur_feed_url" \
			--arg content_dir "release-notes/${X}/${X}.0/api-diff" \
			--arg cur_milestone "$head_undotted" \
			--arg desired_branch "api-diff/${prev_mm}-ga_to_${cur_vm}" \
			--arg status "$status" --arg vmr_ref "$vmr_ref" \
			'{track:$track, major:$major, prev_vm:$prev_vm, cur_vm:$cur_vm,
        previous_version:$previous_version, previous_feed:$previous_feed,
        current_version:$current_version, current_feed:$current_feed,
        content_dir:$content_dir, cur_milestone:$cur_milestone,
        desired_branch:$desired_branch, status:$status, vmr_ref:$vmr_ref}')"
	fi

	# ---- incremental (frontier): previous milestone -> X head ---------------
	pm="$(prev_milestone "$X" "$head_label" "$channel")"
	if [ -n "$pm" ]; then
		IFS='|' read -r inc_prev_vm inc_prev_ver inc_prev_feed <<<"$pm"
		emit "$(jq -cn \
			--arg track incremental --arg major "$X" \
			--arg prev_vm "$inc_prev_vm" --arg cur_vm "$cur_vm" \
			--arg previous_version "$inc_prev_ver" --arg previous_feed "$(feed_index "$inc_prev_feed")" \
			--arg current_version "$cur_ver" --arg current_feed "$cur_feed_url" \
			--arg content_dir "release-notes/${X}/preview/${head_undotted}/api-diff" \
			--arg cur_milestone "$head_undotted" \
			--arg desired_branch "api-diff/${inc_prev_vm}_to_${cur_vm}" \
			--arg status "$status" --arg vmr_ref "$vmr_ref" \
			'{track:$track, major:$major, prev_vm:$prev_vm, cur_vm:$cur_vm,
        previous_version:$previous_version, previous_feed:$previous_feed,
        current_version:$current_version, current_feed:$current_feed,
        content_dir:$content_dir, cur_milestone:$cur_milestone,
        desired_branch:$desired_branch, status:$status, vmr_ref:$vmr_ref}')"
	fi
done

jq -c 'unique_by([.track, .desired_branch]) | sort_by(.major, .track, .cur_vm)' <<<"$targets"
