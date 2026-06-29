---
name: Write API Diff
description: >
  Generate or refresh the public API diff report for a single in-flight .NET
  release milestone (incremental or major-to-major) from real published builds and
  open/update its draft pull request. Invoked per-target by the API Diff Manager
  (workflow_call) or manually (workflow_dispatch).

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
  workflow_call:
    inputs:
      target:
        description: "Single discovery target (JSON) from api-diff-discover.sh."
        required: true
        type: string

steps:
  - name: Preload target context and generate the API diff
    shell: bash
    env:
      TARGET: ${{ inputs.target }}
      GH_TOKEN: ${{ github.token }}
      GH_RUN_ID: ${{ github.run_id }}
    run: |
      set -euo pipefail
      bash .github/scripts/api-diff-producer-preload.sh

post-steps:
  - name: Translate publish manifest to publish-items.json
    run: |
      set -euo pipefail
      manifest_dir=/tmp/gh-aw/agent/publish
      items_file=/tmp/gh-aw/agent/publish-items.json
      mkdir -p /tmp/gh-aw/agent
      echo '{"items":[]}' > "$items_file"

      if [ ! -d "$manifest_dir" ]; then
        echo "No publish manifest was written (nothing to publish)"; exit 0
      fi
      shopt -s nullglob
      manifests=("$manifest_dir"/*.json)
      if [ ${#manifests[@]} -eq 0 ]; then
        echo "No publish manifest was written (nothing to publish)"; exit 0
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
        pr=$(jq -r '.pr_number // empty' "$manifest")

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

        if [ -n "$pr" ]; then
          # Update an existing marker PR.
          ahead=$(git rev-list --count "origin/$branch..$branch" 2>/dev/null || echo 0)
          if [ "$ahead" -gt 0 ]; then
            append_item "$(jq -cn --arg branch "$branch" --arg bundle_path "$bundle_path" \
              --arg message "${comment:-Refreshed API diff.}" --argjson pr "$pr" \
              '{type:"push_to_pull_request_branch", branch:$branch, bundle_path:$bundle_path, message:$message, pull_request_number:$pr}')"
          fi
          if [ -n "$body" ] || [ -n "$title" ]; then
            append_item "$(jq -cn --arg title "$title" --arg body "$body" --argjson pr "$pr" --argjson ready "$ready" \
              '{type:"update_pr_body", title:$title, body:$body, pull_request_number:$pr, ready:$ready}')"
          fi
          if [ -n "$comment" ]; then
            append_item "$(jq -cn --arg body "$comment" --argjson n "$pr" \
              '{type:"add_comment", body:$body, item_number:$n}')"
          fi
        else
          # Open a new draft PR.
          if [ -z "$title" ] || [ -z "$body" ]; then
            echo "New PR manifest must include title and body: $manifest" >&2; exit 1
          fi
          append_item "$(jq -cn --arg branch "$branch" --arg bundle_path "$bundle_path" \
            --arg title "$title" --arg body "$body" --arg comment "$comment" \
            --argjson remote_only "$remote_only" --argjson ready "$ready" \
            '{type:"create_pull_request", branch:$branch, bundle_path:$bundle_path, title:$title, body:$body, comment:$comment, remote_only:$remote_only, ready:$ready}')"
        fi
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
            echo "::notice::No publish-items.json — nothing to publish"; exit 0
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

          mark_ready_if_requested() {
            local num="$1" ready="$2" is_draft
            [ "$ready" = "true" ] || return 0
            is_draft=$(gh pr view "$num" --json isDraft -q '.isDraft' 2>/dev/null || echo false)
            if [ "$is_draft" = "true" ]; then
              gh pr ready "$num" && echo "::notice::PR #$num marked Ready for Review (code complete)"
            fi
          }

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
                existing=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number')
                if [ -n "$existing" ] && [ "$existing" != "null" ]; then
                  num="$existing"
                  echo "::notice::Branch $branch already has PR #$num; refreshing"
                  [ -n "$body" ] && gh pr edit "$num" --title "$title" --body "$body" || true
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

You maintain a **public API diff report** for one in-flight .NET release diff in this
repository (dotnet/core). The report is factual: the `api-diff` skill's `RunApiDiff.ps1`
already generated it during preload from **real published builds** and staged it into the
working tree. Your job is to publish it as a pull request, keep its description accurate,
and act on reviewer feedback — not to author prose. **Never merge**; humans merge.

## 1. Read your context

Read `/tmp/gh-aw/agent/target.json`:

- `track` — `incremental` (milestone-over-milestone) or `major-to-major` (cumulative vs prior major)
- `major`, `prev_vm`, `cur_vm` — the diff identity (e.g. `11.0`, `10.0-ga`, `11.0-preview.7`)
- `previous_version`/`previous_feed`, `current_version`/`current_feed` — exact build versions + feeds
- `vmr_ref`, `vmr_sha` — the dotnet/dotnet VMR ref the current milestone builds from
- `status` — `in-development` (PR stays DRAFT) or `code-complete` (PR is Ready for Review)
- `content_dir` — where the generated reports live
- `overlay_path` — the milestone's attribute-exclusion overlay file
- `marker` — the hidden PR-identity marker; **put it verbatim in the PR body**
- `target_branch` — the branch you publish to (already resolved, including any collision suffix)
- `existing_pr_number` — the open marker PR to update (empty if you should open a new one)
- `produce` — **if `false`, STOP: write no manifest and open no PR** (no build available)
- `report_count`, `excluded_attributes`, `generated_at`

**If `produce` is `false`, do nothing** (the milestone has no build yet; never open an
empty PR, and never disturb an existing PR).

## 2. Review write-access reviewer feedback (only when `existing_pr_number` is set)

Read the PR's review + issue comments. **Act only on feedback from `OWNER`, `MEMBER`, or
`COLLABORATOR`** (`authorAssociation`). The common request is to drop low-value attribute
noise. For each such request:

1. Append the fully-qualified attribute name to the overlay at `overlay_path` (durable —
   future refreshes stay clean because preload merges it into the diff exclusions).
2. Apply it now: remove matching lines from the `.md` files under `content_dir`.
3. Note what you changed in your comment and in the PR body's **Feedback applied** section.

Do not act on feedback that asks for prose, changing the diff semantics, or excluding real
API changes. Leave ambiguous/out-of-scope feedback for a human and say so.

## 3. Stage the branch

```bash
git fetch origin main
git checkout -B "<target_branch>" "origin/<target_branch>" 2>/dev/null || git checkout -B "<target_branch>" origin/main
git add "<content_dir>"
git commit -m "API diff <prev_vm> -> <cur_vm>"
```

Commit only `content_dir` (the reports + the overlay). Touch nothing else.

## 4. Write the publish manifest

Write one JSON file to `/tmp/gh-aw/agent/publish/<safe-branch>.json` (`<safe-branch>` =
`target_branch` with `/` replaced by `_`):

```json
{
  "branch": "<target_branch>",
  "pr_number": "<existing_pr_number or empty>",
  "title": "[api-diff] .NET <cur_vm> — <Incremental|Cumulative> public API diff vs <prev_vm>",
  "body": "<the full PR description, see below>",
  "comment": "<short summary of what changed this run>",
  "ready": <true if status == code-complete, else false>
}
```

Do **not** call the `add_comment` safe-output tool directly — the publish job posts your
`comment` deterministically.

### PR description (`body`)

Lead with the hidden marker on its own line (verbatim from `target.json`):
`<!-- api-diff:<prev_vm>_to_<cur_vm> -->`

Then, succinct and factual:

1. One line: what this diffs — `<prev_vm>` (`previous_version`) -> `<cur_vm>` (`current_version`), and the track.
2. **How this was generated** — the `api-diff` skill / `RunApiDiff.ps1`; the exact
   `previous_version`@`previous_feed` and `current_version`@`current_feed`; the VMR
   `vmr_ref`@`vmr_sha`; `generated_at`; `report_count` files. For **major-to-major**, note
   it is the cumulative diff vs the prior major and refreshes as the head advances.
3. **Status** — `in-development` (draft until the milestone snaps to a release branch) or
   `code-complete` (Ready for Review).
4. **Feedback applied** — every excluded attribute now in effect (union of
   `excluded_attributes` and anything you added this run); "None." only if empty.
5. A fenced ```yaml``` block:

   ```yaml
   track: "<track>"
   prev_vm: "<prev_vm>"
   cur_vm: "<cur_vm>"
   previous_version: "<previous_version>"
   current_version: "<current_version>"
   previous_feed: "<previous_feed>"
   current_feed: "<current_feed>"
   status: "<status>"
   vmr_ref: "<vmr_ref>"
   vmr_sha: "<vmr_sha>"
   report_count: <report_count>
   generated_at: "<generated_at>"
   excluded_attributes: [<every attribute now excluded>]
   ```

## Invariants

- PRs are **always created as drafts**; flip to Ready for Review only when `status` is
  `code-complete` (`"ready": true`). Never un-ready; never merge.
- `produce == false` -> no manifest, no PR.
- Touch only `content_dir`. One PR per diff, identified by the marker.
