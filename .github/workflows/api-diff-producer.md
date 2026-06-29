---
name: Write API Diff
description: >
  Generate or refresh the public API diff report for a single in-flight .NET
  release milestone and open/update its draft pull request. Invoked per-milestone
  by the API Diff Manager (workflow_call) or manually (workflow_dispatch).

if: (!github.event.repository.fork) || github.event_name == 'workflow_dispatch'

permissions:
  actions: read
  contents: read
  pull-requests: read
  issues: read

network:
  allowed:
    - defaults
    - dotnet
safe-outputs:
  add-comment:
    max: 5
    target: "*"
tools:
  bash:
    - pwsh
    - dotnet
    - dnx
    - gh
    - git
    - jq
    - find
    - sed
    - cp
    - mv
    - rm
    - mkdir
    - cat
    - ls
    - pwd
    - echo
    - grep
    - head
    - tail
    - wc
timeout-minutes: 90

on:
  permissions: {}
  workflow_dispatch:
    inputs:
      target:
        description: "Single discovery target (JSON) from api-diff-discover.sh."
        required: true
        type: string
      simulate_from:
        description: "Optional: simulate generation by copying an existing milestone's api-diff (folder name, e.g. preview5)."
        required: false
        type: string
  workflow_call:
    inputs:
      target:
        description: "Single discovery target (JSON) from api-diff-discover.sh."
        required: true
        type: string
      simulate_from:
        description: "Optional: simulate generation from an existing milestone's api-diff."
        required: false
        type: string

steps:
  - name: Preload target context and generate the API diff
    shell: bash
    env:
      TARGET: ${{ inputs.target }}
      SIMULATE_API_DIFF_FROM: ${{ inputs.simulate_from }}
      GH_TOKEN: ${{ github.token }}
    run: |
      set -euo pipefail
      bash .github/scripts/api-diff-producer-preload.sh

post-steps:
  - name: Translate publish manifest to publish-items.json
    run: |
      set -euo pipefail
      manifest_dir=/tmp/gh-aw/agent/publish
      prs_json=/tmp/gh-aw/agent/api-diff-prs.json
      items_file=/tmp/gh-aw/agent/publish-items.json
      mkdir -p /tmp/gh-aw/agent
      echo '{"items":[]}' > "$items_file"
      [ -f "$prs_json" ] || echo '[]' > "$prs_json"

      if [ ! -d "$manifest_dir" ]; then
        echo "No publish manifest was written"; exit 0
      fi
      shopt -s nullglob
      manifests=("$manifest_dir"/*.json)
      if [ ${#manifests[@]} -eq 0 ]; then
        echo "No publish manifest was written"; exit 0
      fi

      append_item() {
        local tmp; tmp=$(mktemp)
        jq --argjson item "$1" '.items += [$item]' "$items_file" > "$tmp"
        mv "$tmp" "$items_file"
      }

      for manifest in "${manifests[@]}"; do
        branch=$(jq -r '.branch // empty' "$manifest")
        title=$(jq -r '.title // empty' "$manifest")
        body=$(jq -r '.body // empty' "$manifest")
        comment=$(jq -r '.comment // empty' "$manifest")
        ready=$(jq -r '.ready // false' "$manifest")

        if [ -z "$branch" ]; then
          echo "Publish manifest is missing branch: $manifest" >&2; exit 1
        fi

        bundle_path=""
        remote_only="false"
        if git show-ref --verify --quiet "refs/heads/$branch"; then
          safe_branch=$(printf '%s' "$branch" | tr '/[:space:]' '__')
          bundle_path="/tmp/gh-aw/aw-${safe_branch}.bundle"
          rm -f "$bundle_path"
          git bundle create "$bundle_path" "refs/heads/$branch"
        elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
          remote_only="true"
        else
          echo "Publish manifest references unknown branch: $branch" >&2; exit 1
        fi

        open_pr=$(jq -c --arg b "$branch" '[.[] | select(.headRefName == $b and .state == "OPEN")] | first' "$prs_json")
        non_open_pr=$(jq -c --arg b "$branch" '[.[] | select(.headRefName == $b and .state != "OPEN")] | first' "$prs_json")

        if [ "$open_pr" != "null" ]; then
          pr_number=$(jq -r '.number' <<<"$open_pr")
          ahead=$(git rev-list --count "origin/$branch..$branch" 2>/dev/null || echo 0)
          if [ "$ahead" -gt 0 ]; then
            append_item "$(jq -cn --arg branch "$branch" --arg bundle_path "$bundle_path" \
              --arg message "${comment:-Refreshed API diff.}" --argjson pr "$pr_number" \
              '{type:"push_to_pull_request_branch", branch:$branch, bundle_path:$bundle_path, message:$message, pull_request_number:$pr}')"
          fi
          if [ -n "$body" ] || [ -n "$title" ]; then
            append_item "$(jq -cn --arg title "$title" --arg body "$body" --argjson pr "$pr_number" --argjson ready "$ready" \
              '{type:"update_pr_body", title:$title, body:$body, pull_request_number:$pr, ready:$ready}')"
          fi
          if [ -n "$comment" ]; then
            append_item "$(jq -cn --arg body "$comment" --argjson n "$pr_number" \
              '{type:"add_comment", body:$body, item_number:$n}')"
          fi
          continue
        fi

        if [ "$non_open_pr" != "null" ]; then
          state=$(jq -r '.state' <<<"$non_open_pr")
          echo "::warning::Skipping $branch: a non-open PR already exists ($state); not creating a replacement" >&2
          continue
        fi

        if [ -z "$title" ] || [ -z "$body" ]; then
          echo "New PR manifest must include title and body: $manifest" >&2; exit 1
        fi
        append_item "$(jq -cn --arg branch "$branch" --arg bundle_path "$bundle_path" \
          --arg title "$title" --arg body "$body" --arg comment "$comment" \
          --argjson remote_only "$remote_only" --argjson ready "$ready" \
          '{type:"create_pull_request", branch:$branch, bundle_path:$bundle_path, title:$title, body:$body, comment:$comment, remote_only:$remote_only, ready:$ready}')"
      done
      echo "publish-items.json:"; jq '.' "$items_file"

jobs:
  publish_api_diff:
    name: Publish API diff branch
    needs: [agent, activation]
    if: always() && needs.agent.result == 'success'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}
          persist-credentials: true
      - name: Download agent artifact
        uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          name: ${{ needs.activation.outputs.artifact_prefix }}agent
          path: /tmp/gh-aw/
      - name: Configure git identity
        run: |
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git config --global user.name "github-actions[bot]"
      - name: Publish API diff PR from agent output
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          items=/tmp/gh-aw/agent/publish-items.json
          if [ ! -f "$items" ]; then
            echo "::notice::No publish-items.json produced — nothing to publish"; exit 0
          fi
          count=$(jq '.items | length' "$items")
          if [ "$count" -eq 0 ]; then
            echo "::notice::publish-items.json had 0 items — nothing to publish"; exit 0
          fi

          resolve_bundle() {
            local p="/tmp/gh-aw/$(basename "$1")"
            [ -f "$p" ] || { echo "::error::Bundle not found: $p" >&2; return 1; }
            printf '%s' "$p"
          }

          # mark_ready_if_requested <pr-number> <ready>
          # Flip a draft PR to Ready for Review once the milestone is code
          # complete. Never un-ready and never merge -- humans own merging.
          mark_ready_if_requested() {
            local num="$1" ready="$2"
            [ "$ready" = "true" ] || return 0
            local is_draft
            is_draft=$(gh pr view "$num" --json isDraft -q '.isDraft' 2>/dev/null || echo false)
            if [ "$is_draft" = "true" ]; then
              gh pr ready "$num" && echo "::notice::PR #$num marked Ready for Review (milestone code complete)"
            fi
          }

          # push_branch <branch> <bundle> -- fetch the agent's branch, rebase
          # onto current origin/main, normalize markdown (MD012 squeeze +
          # markdownlint --fix), gate on markdownlint, then force-push.
          push_branch() {
            local branch="$1" bundle="$2" changed md
            local bundle_local; bundle_local=$(resolve_bundle "$bundle")
            git fetch "$bundle_local" "+refs/heads/$branch:refs/heads/$branch"
            if ! git rebase origin/main "$branch"; then
              git rebase --abort 2>/dev/null || true
              echo "::error::Could not rebase $branch onto origin/main"; return 1
            fi
            git checkout -q "$branch"
            changed=$(git diff --name-only "origin/main...$branch" -- '*.md' 2>/dev/null || true)
            if [ -n "$changed" ]; then
              while IFS= read -r md; do
                [ -f "$md" ] || continue
                cat -s "$md" > "$md.sq" && mv "$md.sq" "$md"
                npx --yes markdownlint-cli --config .github/linters/.markdown-lint.yml --fix "$md" >/dev/null 2>&1 || true
              done <<< "$changed"
              git diff --quiet || git commit -aqm "Normalize API diff markdown"
              # shellcheck disable=SC2086
              if ! npx --yes markdownlint-cli --config .github/linters/.markdown-lint.yml $changed 2>&1; then
                echo "::error::Markdownlint violations on $branch — refusing to push."; return 1
              fi
            fi
            git push origin "refs/heads/$branch:refs/heads/$branch" --force-with-lease
          }

          for i in $(seq 0 $((count - 1))); do
            item=$(jq -c ".items[$i]" "$items")
            type=$(jq -r '.type' <<<"$item")
            case "$type" in
              create_pull_request)
                branch=$(jq -r '.branch' <<<"$item")
                title=$(jq -r '.title' <<<"$item")
                body=$(jq -r '.body // empty' <<<"$item")
                comment=$(jq -r '.comment // empty' <<<"$item")
                ready=$(jq -r '.ready // false' <<<"$item")
                remote_only=$(jq -r '.remote_only // false' <<<"$item")
                bundle=$(jq -r '.bundle_path // empty' <<<"$item")
                echo "→ create_pull_request branch=$branch ready=$ready"
                if [ "$remote_only" != "true" ]; then
                  push_branch "$branch" "$bundle" || continue
                fi
                existing=$(gh pr list --head "$branch" --state open --json number,url --jq '.[0]')
                if [ -n "$existing" ] && [ "$existing" != "null" ]; then
                  num=$(jq -r '.number' <<<"$existing")
                  echo "::notice::Branch $branch updated; existing PR #$num"
                else
                  num=$(gh pr create --draft --base main --head "$branch" --title "$title" --body "$body" --json number -q '.number' 2>/dev/null \
                    || { gh pr create --draft --base main --head "$branch" --title "$title" --body "$body" >/dev/null && gh pr list --head "$branch" --state open --json number -q '.[0].number'; })
                  echo "::notice::Opened draft PR #$num for $branch"
                fi
                [ -n "$comment" ] && gh pr comment "$num" --body "$comment" || true
                mark_ready_if_requested "$num" "$ready"
                ;;
              push_to_pull_request_branch)
                branch=$(jq -r '.branch' <<<"$item")
                bundle=$(jq -r '.bundle_path' <<<"$item")
                push_branch "$branch" "$bundle" || true
                ;;
              update_pr_body)
                num=$(jq -r '.pull_request_number' <<<"$item")
                title=$(jq -r '.title // empty' <<<"$item")
                body=$(jq -r '.body // empty' <<<"$item")
                ready=$(jq -r '.ready // false' <<<"$item")
                if [ -n "$body" ]; then
                  if [ -n "$title" ]; then gh pr edit "$num" --title "$title" --body "$body"; else gh pr edit "$num" --body "$body"; fi
                fi
                mark_ready_if_requested "$num" "$ready"
                ;;
              add_comment)
                num=$(jq -r '.item_number' <<<"$item")
                body=$(jq -r '.body' <<<"$item")
                gh pr comment "$num" --body "$body"
                ;;
            esac
          done

# ###############################################################
# Override COPILOT_GITHUB_TOKEN with a random PAT from the pool.
# This stop-gap will be removed when org billing is available.
# See: .github/workflows/shared/pat_pool.README.md for more info.
# ###############################################################
imports:
  - shared/pat_pool.md

environment: copilot-pat-pool

engine:
  id: copilot
  version: "1.0.60"
  env:
    # We cannot use line breaks in this expression as it leads to a syntax error in the compiled workflow
    COPILOT_GITHUB_TOKEN: ${{ case(needs.pat_pool.outputs.pat_number == '0', secrets.COPILOT_PAT_0, needs.pat_pool.outputs.pat_number == '1', secrets.COPILOT_PAT_1, needs.pat_pool.outputs.pat_number == '2', secrets.COPILOT_PAT_2, needs.pat_pool.outputs.pat_number == '3', secrets.COPILOT_PAT_3, needs.pat_pool.outputs.pat_number == '4', secrets.COPILOT_PAT_4, needs.pat_pool.outputs.pat_number == '5', secrets.COPILOT_PAT_5, needs.pat_pool.outputs.pat_number == '6', secrets.COPILOT_PAT_6, needs.pat_pool.outputs.pat_number == '7', secrets.COPILOT_PAT_7, needs.pat_pool.outputs.pat_number == '8', secrets.COPILOT_PAT_8, needs.pat_pool.outputs.pat_number == '9', secrets.COPILOT_PAT_9, secrets.COPILOT_GITHUB_TOKEN) }}
    GITHUB_TOKEN: ${{ github.token }}
---

<!-- markdownlint-disable-next-line MD025 -->
# Write API Diff

You maintain the **public API diff report** for a single in-flight .NET release
milestone in this repository (dotnet/core). The report is a factual artifact:
the `api-diff` skill's `RunApiDiff.ps1` produced it during preload and staged it
into the working tree. Your job is to publish it as a **draft pull request**,
keep its description accurate, and act on reviewer feedback — not to author prose.

This is a **live system**: humans leave PR feedback and may edit the branch at
any time. Respect their changes. **Never merge** and never mark a PR Ready for
Review yourself except via the code-complete rule below.

## 1. Read your context

Read `/tmp/gh-aw/agent/target.json`. It contains:

- `major`, `milestone`, `milestone_dotted` — the milestone identity (e.g. `11.0`, `preview6`, `preview.6`)
- `vmr_ref`, `vmr_sha` — the dotnet/dotnet VMR ref the milestone is built from
- `status` — `in-development` (PR stays DRAFT) or `code-complete` (PR is Ready for Review)
- `base_branch` — the PR head branch you publish to (e.g. `api-diff/11.0-preview.6`)
- `content_dir` — where the generated reports live (`release-notes/<major>/preview/<milestone>/api-diff`)
- `overlay_path` — the milestone's attribute-exclusion overlay file
- `generated` — `true` if reports were produced this run; `false` if generation is pending (ref packs not yet published)
- `report_count`, `generated_at`

## 2. Review write-access reviewer feedback

Find the existing PR for `base_branch`:

```bash
gh pr list --head "<base_branch>" --state open --json number,isDraft,reviews,comments
```

Read its review comments and issue comments. **Only act on feedback from users
with write access** — check each comment/review `authorAssociation` and act only
on `OWNER`, `MEMBER`, or `COLLABORATOR`. The most common request is to **remove
low-value attribute noise** (e.g. `[System.Runtime.CompilerServices.NullableAttribute]`,
`[System.Runtime.CompilerServices.NullableContextAttribute]`). For each such
request:

1. Append the fully-qualified attribute name (one per line) to the overlay file
   at `overlay_path`. This makes the exclusion **durable** — every future refresh
   stays clean because the preload merges the overlay into the diff's exclusions.
2. Apply it **immediately** to the already-generated reports so the current PR
   reflects it: remove matching lines from the `.md` files under `content_dir`.
3. Note exactly what you changed in your update comment.

Do **not** act on feedback that asks you to author prose, change the diff
semantics, or exclude real API changes. If feedback is ambiguous or out of
scope, leave it for a human and say so in the comment.

## 3. Stage the branch

Save the publish branch (`base_branch` from target.json), then:

```bash
git fetch origin main
# Start from the existing PR branch if it exists, else from main:
git checkout -B "<base_branch>" "origin/<base_branch>" 2>/dev/null || git checkout -B "<base_branch>" origin/main
git add "<content_dir>"
git commit -m "Update API diff for <major> <milestone_dotted>"
```

Only commit the `content_dir` (the api-diff reports and the overlay). Do not
touch unrelated files.

## 4. Write the publish manifest

Write exactly one JSON file to `/tmp/gh-aw/agent/publish/<safe-branch>.json`
(create the directory; `<safe-branch>` is the branch with `/` replaced by `_`):

```json
{
  "branch": "<base_branch>",
  "title": "[api-diff] .NET <major> <Milestone> — Public API diff",
  "body": "<the full PR description, see below>",
  "comment": "<a short summary of what changed this run>",
  "ready": <true if status == code-complete, else false>
}
```

Do **not** call the `add_comment` safe-output tool directly — the publish job
posts your `comment` deterministically after pushing.

### PR description (`body`)

Write a concise, factual description. Include, in this order:

1. A one-line summary: what milestone this diffs and against what previous milestone.
2. A **How this was generated** section: the `api-diff` skill / `RunApiDiff.ps1`, the
   VMR ref (`vmr_ref`) and `vmr_sha`, `generated_at`, and `report_count` report files.
   If `generated` is `false`, clearly state the diff is **pending** because the
   milestone's reference packages are not yet published, and that it will populate
   on a later refresh.
3. A **Status** line: `in-development` (kept as a draft until the milestone snaps
   to a release branch) or `code-complete` (the milestone has snapped; this PR is
   Ready for Review).
4. A **Feedback applied** section listing any attributes you excluded this run (or
   "None").
5. A fenced ```yaml``` codeblock capturing the current reference state:

   ```yaml
   major: "<major>"
   milestone: "<milestone_dotted>"
   status: "<status>"
   vmr_ref: "<vmr_ref>"
   vmr_sha: "<vmr_sha>"
   generated: <generated>
   report_count: <report_count>
   generated_at: "<generated_at>"
   excluded_attributes: [<the overlay entries>]
   ```

Keep it succinct and bullet-driven. The reports speak for themselves; do not
restate them.

## Invariants

- PRs are **always created as drafts**. They flip to Ready for Review only when
  `status` is `code-complete` (set `"ready": true`). Never un-ready a PR; never merge.
- If `generated` is `false` and there is no existing report content, still open
  the draft PR with the pending status so the milestone is tracked.
- Touch only `content_dir`. One PR per milestone, on the exact `base_branch`.
