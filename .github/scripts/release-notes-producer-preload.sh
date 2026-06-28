#!/usr/bin/env bash
# release-notes-producer-preload.sh
#
# Deterministic, single-target preload for the Release Notes Producer (FEATURE
# mode). Runs on the host before the agent (the agent's sandbox cannot reach or
# execute the release-notes tool), so the agent consumes the pre-generated
# changes.json / build-metadata.json instead of producing them itself.
#
# Split out of the release-notes-preload composite action (kept off the agentic
# `steps:` block because gh-aw v0.80.9 cannot pin a local composite action).
#
# For one FEATURE target it:
#   1. clones the dotnet/dotnet VMR (blobless) if not already present,
#   2. resolves the base tag and the in-flight head ref (with the main->branch
#      transition rule),
#   3. generates changes.json and build-metadata.json into the target's gen dir,
#   4. preloads the target's existing release-notes PR context (PR body, issue +
#      review comments) so the agent can respect human edits and feedback.
#
# Requires `release-notes`, `git`, `gh`, and `jq` on PATH.
#
# Inputs (env):
#   TARGET      required  single target object (JSON) emitted by discovery
#   VMR_PATH    optional  VMR clone path                 (default /tmp/dotnet)
#   AGENT_DIR   optional  agent context dir              (default /tmp/gh-aw/agent)
#   GH_TOKEN    required for PR-context preload
set -euo pipefail

TARGET="${TARGET:?TARGET (single target JSON) is required}"
VMR_PATH="${VMR_PATH:-/tmp/dotnet}"
AGENT_DIR="${AGENT_DIR:-/tmp/gh-aw/agent}"

mode="$(jq -r '.mode' <<<"$TARGET")"
if [ "$mode" != "feature" ]; then
  echo "::error::release-notes-producer-preload.sh handles FEATURE targets; got mode='$mode'" >&2
  exit 1
fi

major="$(jq -r '.major' <<<"$TARGET")"
base_tag="$(jq -r '.vmr_base_tag' <<<"$TARGET")"
head_ref="$(jq -r '.vmr_head_ref' <<<"$TARGET")"
version="$(jq -r '.release_version' <<<"$TARGET")"
base_branch="$(jq -r '.base_branch' <<<"$TARGET")"

gen_dir="${AGENT_DIR}/generated/${base_branch#release-notes/}"
gen_changes="${gen_dir}/changes.json"
gen_build_metadata="${gen_dir}/build-metadata.json"
mkdir -p "$gen_dir" "$AGENT_DIR/pr-comments"

# ---- 1. VMR clone ----------------------------------------------------------
if [ ! -d "$VMR_PATH/.git" ]; then
  echo "::group::clone VMR -> $VMR_PATH"
  git clone --filter=blob:none https://github.com/dotnet/dotnet "$VMR_PATH"
  echo "::endgroup::"
fi
git -C "$VMR_PATH" rev-parse --verify HEAD >/dev/null

# ---- 2. resolve refs -------------------------------------------------------
if ! git -C "$VMR_PATH" rev-parse --verify "$base_tag" >/dev/null 2>&1; then
  echo "::error::VMR base ref '$base_tag' for $major does not resolve in $VMR_PATH" >&2
  git -C "$VMR_PATH" for-each-ref --format='%(refname:short)' 'refs/tags/v*' | grep -F "${major%.*}" | tail -10 || true
  exit 1
fi

# head_ref is the in-flight milestone branch; pin to it once it exists, else
# draft against main (the leading edge). Falling back to main is expected.
head="$head_ref"
if [ "$head" != "main" ]; then
  if git -C "$VMR_PATH" rev-parse --verify --quiet "origin/$head^{commit}" >/dev/null 2>&1; then
    git -C "$VMR_PATH" branch -f "$head" "origin/$head" >/dev/null 2>&1 || true
    echo "::notice::$major head pinned to milestone branch '$head'."
  elif git -C "$VMR_PATH" rev-parse --verify --quiet "$head^{commit}" >/dev/null 2>&1; then
    echo "::notice::$major head pinned to '$head'."
  else
    echo "::notice::$major head branch '$head' not present yet; drafting against 'main'."
    head="main"
  fi
fi

# ---- 3. deterministic generation -------------------------------------------
echo "::group::generate changes ($major $version): base=$base_tag head=$head"
release-notes generate changes "$VMR_PATH" \
  --base "$base_tag" \
  --head "$head" \
  --version "$version" \
  --labels \
  --output "$gen_changes"
echo "::endgroup::"

echo "::group::generate build-metadata ($major): base=$base_tag head=$head"
if release-notes generate build-metadata "$VMR_PATH" \
  --base "$base_tag" \
  --head "$head" \
  --output "$gen_build_metadata"; then
  echo "build-metadata generated."
else
  echo "::warning::build-metadata generation failed for $major (head=$head) — most likely the head build's packages are not published on the feed yet. The agent should preserve any existing build-metadata.json on the features branch."
  rm -f "$gen_build_metadata"
fi
echo "::endgroup::"

# ---- 4. PR context preload -------------------------------------------------
if [ -n "${GH_TOKEN:-}" ]; then
  echo "::group::preload PR context for $base_branch"
  pr_json="${AGENT_DIR}/release-notes-pr.json"
  gh pr list \
    --repo "$GITHUB_REPOSITORY" \
    --search "[release-notes] in:title" \
    --state all \
    --limit 100 \
    --json number,title,body,headRefName,baseRefName,state,isDraft,url,updatedAt,author \
    > "${AGENT_DIR}/release-notes-prs.json" 2>/dev/null || echo "[]" > "${AGENT_DIR}/release-notes-prs.json"

  # The PR(s) belonging to this target: base branch + its component sub-branches.
  jq --arg base "$base_branch" \
    '[.[] | select(.headRefName == $base or (.headRefName | startswith($base + "-")))]' \
    "${AGENT_DIR}/release-notes-prs.json" > "$pr_json"

  jq -r '.[] | select(.state == "OPEN") | .number' "$pr_json" | while IFS= read -r pr; do
    [ -n "$pr" ] || continue
    gh api "repos/$GITHUB_REPOSITORY/issues/$pr/comments?per_page=100" > "$AGENT_DIR/pr-comments/${pr}-issue-comments.json" 2>/dev/null || true
    gh api "repos/$GITHUB_REPOSITORY/pulls/$pr/comments?per_page=100"  > "$AGENT_DIR/pr-comments/${pr}-review-comments.json" 2>/dev/null || true
    gh api "repos/$GITHUB_REPOSITORY/pulls/$pr/reviews?per_page=100"   > "$AGENT_DIR/pr-comments/${pr}-reviews.json" 2>/dev/null || true
  done
  echo "::endgroup::"
else
  echo "::notice::GH_TOKEN not set — skipping PR-context preload."
fi

echo "Producer preload complete for ${base_branch}:"
find "$gen_dir" -type f 2>/dev/null | sort
