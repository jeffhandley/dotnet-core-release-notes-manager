---
if: (!github.event.repository.fork) || github.event_name == 'workflow_dispatch'

permissions:
  actions: read
  contents: read
  pull-requests: read

runtimes:
  dotnet:
    version: "11.0"
network:
  allowed:
    - defaults
    - dotnet
tools:
  bash:
    - gh
    - git
    - jq
    - mkdir
    - cp
    - mv
    - rm
    - chmod
    - cat
    - ls
    - pwd
    - echo
    - grep
    - sed
    - npx
    - node
    - bash
timeout-minutes: 60

on:
  permissions: {}
  workflow_run:
    workflows: ["Write Release Notes"]
    types: [completed]
    branches:
      - main
  workflow_dispatch:
    inputs:
      source_run_id:
        description: "Write Release Notes run ID to recover blocked branches from. Leave empty to use the most recent completed run."
        required: false
        type: string

steps:
  - name: Determine source run id
    id: source-run
    env:
      GH_TOKEN: ${{ github.token }}
      INPUT_RUN_ID: ${{ github.event.inputs.source_run_id }}
      WORKFLOW_RUN_ID: ${{ github.event.workflow_run.id }}
    run: |
      set -euo pipefail
      if [ -n "${INPUT_RUN_ID:-}" ]; then
        run_id="$INPUT_RUN_ID"
      elif [ -n "${WORKFLOW_RUN_ID:-}" ]; then
        run_id="$WORKFLOW_RUN_ID"
      else
        run_id=$(gh run list -R "$GITHUB_REPOSITORY" \
          --workflow "Write Release Notes" \
          --status completed --limit 1 \
          --json databaseId --jq '.[0].databaseId')
      fi
      [ -n "$run_id" ] || { echo "No source run available"; exit 1; }
      echo "run_id=$run_id" >> "$GITHUB_OUTPUT"
      echo "Source Write Release Notes run: $run_id"

  - name: Download agent artifact from source run
    uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
    with:
      name: agent
      path: /tmp/source-run
      run-id: ${{ steps.source-run.outputs.run_id }}
      github-token: ${{ github.token }}

  - name: Identify blocked branches and prepare working trees
    env:
      GH_TOKEN: ${{ github.token }}
    run: |
      set -euo pipefail
      mkdir -p /tmp/gh-aw/agent
      targets="/tmp/gh-aw/agent/fixup-targets.json"
      echo '[]' > "$targets"

      source "$GITHUB_WORKSPACE/.github/scripts/release-notes-publish-prep.sh"
      setup_toc_tool

      git config user.email "actions@github.com"
      git config user.name "github-actions[bot]"
      # Bundles from the source run are incremental against full history.
      # The default checkout is shallow (depth=1), so unshallow before fetching bundles.
      git fetch --unshallow origin 2>/dev/null || git fetch origin
      git fetch --quiet origin main

      shopt -s nullglob
      bundles=(/tmp/source-run/aw-release-notes_*.bundle)
      if [ ${#bundles[@]} -eq 0 ]; then
        echo "No release-notes bundles in source run — nothing to fix."
        exit 0
      fi

      for bundle in "${bundles[@]}"; do
        base=$(basename "$bundle" .bundle)
        # aw-release-notes_dotnet-11-preview-5-features-sdk -> release-notes/dotnet-11-preview-5-features-sdk
        branch="release-notes/${base#aw-release-notes_}"

        echo ">>> Evaluating $branch"
        if ! git bundle verify "$bundle" >/dev/null 2>&1; then
          echo "  bundle invalid — skipping"
          continue
        fi

        # Get the branch tip from the bundle into a local ref. The bundle may
        # carry the branch under refs/heads/$branch.
        if ! git fetch --quiet "$bundle" "+refs/heads/$branch:refs/heads/$branch" 2>/dev/null; then
          echo "  bundle does not contain refs/heads/$branch — skipping"
          continue
        fi

        # Skip if already on origin (the main workflow already pushed it).
        if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
          remote_sha=$(git ls-remote --heads origin "$branch" | awk '{print $1}')
          local_sha=$(git rev-parse "$branch")
          if [ "$remote_sha" = "$local_sha" ]; then
            echo "  already on origin at same SHA — skipping"
            continue
          fi
        fi

        # Check out the branch and rebase onto current main.
        git checkout -q "$branch"
        if ! git rebase origin/main "$branch" >/dev/null 2>&1; then
          git rebase --abort 2>/dev/null || true
          echo "  rebase conflict — cannot fix automatically, skipping"
          continue
        fi

        # Regenerate TOC.
        regenerate_tocs "$branch"

        # Run lint. If clean, we don't need the agent for this branch.
        lint_out="/tmp/gh-aw/agent/lint-$branch.txt"
        mkdir -p "$(dirname "$lint_out")"
        if lint_branch "$branch" "$lint_out"; then
          echo "  lint clean after rebase+TOC — adding as direct-push target"
          jq --arg b "$branch" '. += [{branch: $b, needs_agent: false, violations: ""}]' "$targets" > "$targets.tmp"
          mv "$targets.tmp" "$targets"
        else
          echo "  lint failed — adding as agent-fixup target"
          violations=$(cat "$lint_out")
          jq --arg b "$branch" --arg v "$violations" \
            '. += [{branch: $b, needs_agent: true, violations: $v}]' "$targets" > "$targets.tmp"
          mv "$targets.tmp" "$targets"
        fi
      done

      echo "---"
      echo "Fixup targets:"
      jq '.' "$targets"

      # Capture branches the agent must touch so the agent step can short-circuit.
      needs_agent_count=$(jq '[.[] | select(.needs_agent)] | length' "$targets")
      echo "needs_agent_count=$needs_agent_count" >> "$GITHUB_ENV"

post-steps:
  - name: Bundle fixed branches for publish job
    env:
      GH_TOKEN: ${{ github.token }}
    run: |
      set -euo pipefail
      targets="/tmp/gh-aw/agent/fixup-targets.json"
      [ -f "$targets" ] || { echo "No targets — nothing to bundle."; exit 0; }

      source "$GITHUB_WORKSPACE/.github/scripts/release-notes-publish-prep.sh"
      setup_toc_tool

      git config user.email "actions@github.com"
      git config user.name "github-actions[bot]"

      # Output manifest for the publish job to consume.
      bundles_dir="/tmp/gh-aw/agent/fixup-bundles"
      mkdir -p "$bundles_dir"
      out="/tmp/gh-aw/agent/fixup-bundles.json"
      echo '[]' > "$out"

      count=$(jq 'length' "$targets")
      for i in $(seq 0 $((count - 1))); do
        branch=$(jq -r ".[$i].branch" "$targets")
        needs_agent=$(jq -r ".[$i].needs_agent" "$targets")

        if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
          jq --arg b "$branch" '. += [{branch: $b, status: "missing-ref"}]' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
          continue
        fi
        git checkout -q "$branch"

        # Re-regen TOC and re-lint after agent edits.
        regenerate_tocs "$branch"
        lint_out="/tmp/gh-aw/agent/post-lint-${branch//\//__}.txt"
        if ! lint_branch "$branch" "$lint_out"; then
          violations=$(cat "$lint_out" 2>/dev/null || echo "")
          jq --arg b "$branch" --arg v "$violations" \
             '. += [{branch: $b, status: "still-blocked", violations: $v}]' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
          continue
        fi

        # Lint clean — bundle the branch tip so the publish job can push.
        safe_branch="${branch//\//__}"
        bundle="$bundles_dir/$safe_branch.bundle"
        git bundle create "$bundle" "refs/heads/$branch" >/dev/null
        jq --arg b "$branch" --arg p "$bundle" --arg src "$needs_agent" \
           '. += [{branch: $b, status: "ready", bundle_path: $p, needed_agent: ($src == "true")}]' \
           "$out" > "$out.tmp" && mv "$out.tmp" "$out"
      done

      echo "Fixup bundle manifest:"
      jq '.' "$out"

jobs:
  publish_fixed_branches:
    name: Publish fixed release-notes branches
    needs: [agent]
    if: always() && needs.agent.result == 'success'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: read
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
          name: agent
          path: /tmp/gh-aw/

      - name: Configure git identity
        run: |
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git config --global user.name "github-actions[bot]"

      - name: Push fixed branches
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          manifest="/tmp/gh-aw/agent/fixup-bundles.json"
          summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
          {
            echo "## Release notes lint fixup"
            echo ""
          } >> "$summary"

          if [ ! -f "$manifest" ]; then
            echo "_No fixup manifest — nothing to publish._" >> "$summary"
            exit 0
          fi

          count=$(jq 'length' "$manifest")
          if [ "$count" -eq 0 ]; then
            echo "_No fixup targets — nothing to publish._" >> "$summary"
            exit 0
          fi

          # The bundle paths in the manifest were written by the agent job
          # using absolute paths under /tmp/gh-aw/agent/fixup-bundles/. The
          # download-artifact step puts them under /tmp/gh-aw/agent/, so the
          # original paths still resolve.
          any_pushed=0
          for i in $(seq 0 $((count - 1))); do
            branch=$(jq -r ".[$i].branch" "$manifest")
            status=$(jq -r ".[$i].status" "$manifest")
            needed_agent=$(jq -r ".[$i].needed_agent // false" "$manifest")
            case "$status" in
              ready)
                bundle=$(jq -r ".[$i].bundle_path" "$manifest")
                if [ ! -f "$bundle" ]; then
                  # Resolve by basename under the downloaded artifact tree.
                  bundle="/tmp/gh-aw/agent/fixup-bundles/$(basename "$bundle")"
                fi
                if [ ! -f "$bundle" ]; then
                  echo "- ❌ \`$branch\` — bundle missing in artifact" >> "$summary"
                  continue
                fi
                git fetch "$bundle" "+refs/heads/$branch:refs/heads/$branch"
                push_args=(origin "refs/heads/$branch:refs/heads/$branch")
                if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
                  remote_sha=$(git ls-remote --heads origin "$branch" | awk '{print $1}')
                  push_args=("--force-with-lease=$branch:$remote_sha" "${push_args[@]}")
                fi
                if git push "${push_args[@]}"; then
                  compare="https://github.com/$GITHUB_REPOSITORY/compare/main...${branch//\//%2F}?expand=1"
                  if [ "$needed_agent" = "true" ]; then
                    echo "- 🤖 \`$branch\` — agent fixed lint violations; pushed. [Open PR]($compare)" >> "$summary"
                  else
                    echo "- ✅ \`$branch\` — TOC regen / rebase resolved lint; pushed. [Open PR]($compare)" >> "$summary"
                  fi
                  any_pushed=1
                else
                  echo "- ❌ \`$branch\` — push rejected (lease conflict?)" >> "$summary"
                fi
                ;;
              still-blocked)
                violations=$(jq -r ".[$i].violations" "$manifest")
                {
                  echo "- ❌ \`$branch\` — still has lint violations after fixup; not pushed"
                  echo "  <details><summary>Violations</summary>"
                  echo ""
                  echo '  ```'
                  printf '%s\n' "$violations" | sed 's/^/  /'
                  echo '  ```'
                  echo "  </details>"
                } >> "$summary"
                ;;
              missing-ref)
                echo "- ⚠️ \`$branch\` — local ref vanished after agent step" >> "$summary"
                ;;
              *)
                echo "- ❓ \`$branch\` — unknown status \`$status\`" >> "$summary"
                ;;
            esac
          done

          if [ "$any_pushed" = "0" ]; then
            echo "" >> "$summary"
            echo "_No branches were pushed._" >> "$summary"
          fi

# ###############################################################
# Override COPILOT_GITHUB_TOKEN with a random PAT from the pool.
# This stop-gap will be removed when org billing is available.
# See: .github/workflows/shared/pat_pool.README.md for more info.
# ###############################################################
imports:
  - shared/pat_pool.md

engine:
  id: copilot
  version: "1.0.60"
  env:
    # If none of the COPILOT_PAT_# secrets were selected, fall back to COPILOT_GITHUB_TOKEN.
    COPILOT_GITHUB_TOKEN: ${{ case(needs.pat_pool.outputs.pat_number == '0', secrets.COPILOT_PAT_0, needs.pat_pool.outputs.pat_number == '1', secrets.COPILOT_PAT_1, needs.pat_pool.outputs.pat_number == '2', secrets.COPILOT_PAT_2, needs.pat_pool.outputs.pat_number == '3', secrets.COPILOT_PAT_3, needs.pat_pool.outputs.pat_number == '4', secrets.COPILOT_PAT_4, needs.pat_pool.outputs.pat_number == '5', secrets.COPILOT_PAT_5, needs.pat_pool.outputs.pat_number == '6', secrets.COPILOT_PAT_6, needs.pat_pool.outputs.pat_number == '7', secrets.COPILOT_PAT_7, needs.pat_pool.outputs.pat_number == '8', secrets.COPILOT_PAT_8, needs.pat_pool.outputs.pat_number == '9', secrets.COPILOT_PAT_9, secrets.COPILOT_GITHUB_TOKEN) }}
    GITHUB_TOKEN: ${{ github.token }}

---

# Fix Release Notes Lint

This workflow runs an agent fixup pass against release-notes branches that the main `Write Release Notes` workflow generated but could **not** push because they failed the markdownlint gate. Bad markdown is **never pushed to origin** — fixups are applied locally and only clean output reaches a remote branch.

## Activation

- **Auto:** `workflow_run` after `Write Release Notes` completes (any conclusion). The pre-step inspects the source run's agent bundles; if nothing is blocked, the agent step short-circuits.
- **Manual:** `workflow_dispatch` with optional `source_run_id` (defaults to the most recent completed `Write Release Notes` run).

## What the pre-steps do (deterministic — no agent)

For each `aw-release-notes_*.bundle` artifact in the source run:

1. Fetch the bundle's `refs/heads/<branch>` into a local ref.
2. Skip if `origin/<branch>` already matches (main workflow pushed it cleanly).
3. Check out the branch and `git rebase origin/main` (skip on conflict).
4. Regenerate `<!-- toc -->` content via `github-slugger`.
5. Run `markdownlint-cli` against the .md files this branch added or modified vs `origin/main`.
6. If clean: queue for direct push (no agent needed).
7. If not: queue for agent fixup, including the violations.

`/tmp/gh-aw/agent/fixup-targets.json` records every queued branch with `needs_agent: true|false` and the violation text. If no entry has `needs_agent: true`, the agent step has nothing to do.

## Your task as the agent

You are a **markdown lint fixer**. Read `/tmp/gh-aw/agent/fixup-targets.json`. For each entry where `needs_agent: true`:

1. `git checkout <branch>` — the working tree is already on the rebased branch with TOC regenerated.
2. Read the `violations` field. Each violation cites a file path, a line number, a rule ID (`MDxxx`), and context.
3. Fix **only** the cited lint violations plus the smallest **obvious adjacent** issues (a typo in a heading that breaks an anchor, an emphasis-line that should be a heading, a missing language tag on a fenced code block). Do not add or remove release-notes content. Do not rewrite paragraphs. Do not edit files outside the cited path unless an adjacent file's link target has been retitled.
4. After editing, `git add` and `git commit --amend --no-edit` (squash into the tip — the post-step rebases and force-with-leases).
5. Re-run `npx --yes markdownlint-cli --config .github/linters/.markdown-lint.yml <file>` against each changed file. If it still reports violations, repeat once. **Maximum two fix attempts per branch.** If the branch is not clean after two attempts, **leave it as-is** — the post-step will report it as still-blocked and the next main-workflow run can re-attempt.
6. Move to the next branch.

## Editorial constraints

These rules come from `.github/skills/dotnet-release-notes/references/editorial-rules.md` and apply to every edit you make:

- **Backtick code identifiers in headings.** Type names, methods, directives, namespaces, constants must be in backticks. Unticked `#:ref`, `<TItem>`, etc. break MD051. Example fix: `## File-based apps: #:ref directive` → `` ## File-based apps: `#:ref` directive ``. After retitling a heading, re-run TOC regen on the file: `( cd /tmp/toctool && node regen-toc.js "$GITHUB_WORKSPACE/<file>" )`.
- **Every fenced code block has a language.** ` ```csharp `, ` ```bash `, ` ```json `, ` ```text `. Use `text` when nothing else fits. A bare ` ``` ` always fails MD040.
- **TOC content is auto-generated.** Never hand-edit lines between `<!-- toc -->` and `<!-- tocstop -->`. If a TOC entry is wrong, fix the underlying heading (or re-run the regenerator) — do not touch the TOC entries directly.

## Do **not**

- Do not spawn sub-agents via the Task tool. Do the work yourself in this conversation. (Sub-agent output is not captured in the publish manifest.)
- Do not regenerate content. You are fixing lint violations, not authoring.
- Do not push branches yourself — the post-step does that after re-linting.
- Do not delete branches. If a branch cannot be fixed in two attempts, abandon it; the next main run will retry.
