---
name: api-diff
description: >
  Generate before/after public-API diff reports for a .NET build or release
  milestone using RunApiDiff.ps1, producing the repo-shaped markdown api-diff/
  output. Pure report generation; to verify that diffed APIs actually shipped,
  use the api-diff-validation skill.
---

# API Diff Generation

Generate the **before/after public-API diff** for a .NET build or release
milestone as repo-shaped markdown (the `api-diff/` reports). This skill is **pure
report generation**.

To *verify* that the diffed APIs actually shipped — catching missed reverts,
renames, and kept-internal APIs, and cross-referencing new APIs against PRs — use
the **`api-diff-validation`** skill (which wraps `dotnet-inspect`).

## Generate the diff with `RunApiDiff.ps1`

When you want the markdown-ready, repo-shaped API diff output, use
`release-notes/RunApiDiff.ps1`. See
[release-notes/RunApiDiff.md](../../../release-notes/RunApiDiff.md) for the full
parameter reference.

## Mapping natural language to parameters

| User says                                             | Parameters                                                                                                             |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| "generate the next API diff"                          | _(none)_                                                                                                               |
| ".NET 10 GA vs .NET 11 Preview 1"                     | `-PreviousMajorMinor 10.0 -CurrentMajorMinor 11.0 -CurrentPrereleaseLabel preview.1`                                   |
| "net9.0-preview6 to net10.0-preview5"                 | `-PreviousMajorMinor 9.0 -PreviousPrereleaseLabel preview.6 -CurrentMajorMinor 10.0 -CurrentPrereleaseLabel preview.5` |
| ".NET 10 RC 2 vs .NET 10 GA"                          | `-PreviousMajorMinor 10.0 -PreviousPrereleaseLabel rc.2 -CurrentMajorMinor 10.0`                                       |
| "10.0.0-preview.7.25380.108 to 10.0.0-rc.1.25451.107" | `-PreviousVersion "10.0.0-preview.7.25380.108" -CurrentVersion "10.0.0-rc.1.25451.107"`                                |

- **GA** or no qualifier -> omit the `PrereleaseLabel` parameter for `RunApiDiff.ps1`; if a downstream api-diff release label is needed, use `ga`
- **Preview N** / **previewN** -> `-PrereleaseLabel preview.N` (for example, `preview.4`, not `preview4`)
- **RC N** / **rcN** -> `-PrereleaseLabel rc.N`
- **netX.Y-previewN** (TFM format) -> `-MajorMinor X.Y -PrereleaseLabel preview.N`
- Full NuGet version strings -> use `-PreviousVersion` / `-CurrentVersion` directly
- The "previous" version is always the older version; "current" is the newer one

## Running the script

```powershell
.\release-notes\RunApiDiff.ps1 [mapped parameters]
```

Set an initial wait of at least 300 seconds — the script takes several minutes. After completion, summarize the results: how many diff files were generated and where.
