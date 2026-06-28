# SDK & Tooling in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new SDK and CLI improvements:

<!-- toc -->

- [MCP server project template bundled with the SDK](#mcp-server-project-template-bundled-with-the-sdk)
- [`dotnet test` improvements](#dotnet-test-improvements)
- [`dotnet watch` warns when `MetadataUpdaterSupport` is `false`](#dotnet-watch-warns-when-metadataupdatersupport-is-false)
- [`dotnet tool update` shows the existing version](#dotnet-tool-update-shows-the-existing-version)
- [File-based apps: custom included item types](#file-based-apps-custom-included-item-types)
- [New `NETSDK1241` diagnostic for empty `TargetFramework`](#new-netsdk1241-diagnostic-for-empty-targetframework)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

.NET SDK updates in .NET 11:

- [What's new in .NET 11](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-11/sdk)

## MCP server project template bundled with the SDK

A new `mcpserver` project template is now included with the .NET 11 SDK ([dotnet/sdk #54132](https://github.com/dotnet/sdk/pull/54132)). The template scaffolds an MCP (Model Context Protocol) server using `Microsoft.Extensions.AI` and the MCP server SDK, ready for use with GitHub Copilot, Claude, and other AI tools that speak the MCP protocol:

```bash
dotnet new mcpserver -n MyMcpServer
```

The generated project includes:

- A `Program.cs` with the MCP server host wired up
- Tool definitions using the `[McpTool]` attribute
- A `.http` file for testing with HTTP+SSE transport

This joins the existing `mcpclient` template and makes it easy to build and ship custom tools for AI assistants directly from the .NET CLI.

## `dotnet test` improvements

### New `--no-dependencies` option

`dotnet test` now supports `--no-dependencies`, which skips building referenced projects before running tests ([dotnet/sdk #54435](https://github.com/dotnet/sdk/pull/54435)). This mirrors the equivalent flag on `dotnet build` and is useful in CI pipelines that perform a full build step before running tests and don't want the test step to re-trigger builds:

```bash
dotnet build MyApp.sln
dotnet test MyApp.sln --no-build --no-dependencies
```

### Terminal logger arguments forwarded to MSBuild

When `dotnet test` invokes MSBuild, it now forwards terminal logger arguments (`-tl`, `--terminalLogger`) to the MSBuild invocation ([dotnet/sdk #54310](https://github.com/dotnet/sdk/pull/54310)). Previously, terminal logger arguments were consumed by the `dotnet test` layer but not passed through to the underlying MSBuild process, so the build output used the wrong logger.

## `dotnet watch` warns when `MetadataUpdaterSupport` is `false`

`dotnet watch` now emits a warning when the target project has `MetadataUpdaterSupport=false`, which disables Hot Reload ([dotnet/sdk #54264](https://github.com/dotnet/sdk/pull/54264)). Previously the watch session would start and appear to work, but changes would trigger a full restart instead of a hot update. The warning makes it explicit when Hot Reload is unavailable and why.

## `dotnet tool update` shows the existing version

`dotnet tool update` now includes the currently installed version in its output messages, so the update log shows both the before and after version in a single line ([dotnet/sdk #54192](https://github.com/dotnet/sdk/pull/54192)):

```text
Tool 'dotnet-ef' was successfully updated from version '10.0.0' to version '11.0.0-preview.6'.
```

## File-based apps: custom included item types

File-based apps (single `.cs` file apps without a project file) now correctly handle conversion of custom item types that are explicitly included in the app's implicit MSBuild items ([dotnet/sdk #54251](https://github.com/dotnet/sdk/pull/54251)). This fixes a class of errors where third-party MSBuild SDKs or custom build logic that added non-standard item types caused file-based app builds to fail during the item-type conversion phase.

## New `NETSDK1241` diagnostic for empty `TargetFramework`

A dedicated diagnostic, `NETSDK1241`, is now emitted when a project's `TargetFramework` property is set to an empty string ([dotnet/sdk #54335](https://github.com/dotnet/sdk/pull/54335)). Previously, an empty `TargetFramework` produced a generic, hard-to-interpret build error. The new diagnostic includes a message that points directly to the offending property and explains that a valid TFM is required.

## Bug fixes

- **SDK** — `dotnet` CLI parser no longer crashes when `global.json` is present but unreadable (permissions error, locked file) ([dotnet/sdk #54433](https://github.com/dotnet/sdk/pull/54433)).
- **Test runner** — Fixed `KeyNotFoundException` in the terminal test reporter's `AssemblyRunCompleted` path ([dotnet/sdk #51608](https://github.com/dotnet/sdk/pull/51608)).
- **`dotnet test` modules** — `--test-modules` now trims whitespace from module paths and supports exclusion glob patterns ([dotnet/sdk #54432](https://github.com/dotnet/sdk/pull/54432)).
- **`--environment` variables** — Environment variables set via `--environment` are now applied to the test process even when no launch profile is active ([dotnet/sdk #53306](https://github.com/dotnet/sdk/pull/53306)).
- **GenAPI** — `notnull` and `allows ref struct` constraints are now preserved in generated API files ([dotnet/sdk #54455](https://github.com/dotnet/sdk/pull/54455)).

## Community contributors

Thank you contributors! ❤️

- [@tmds](https://github.com/tmds) — `--no-dependencies` for `dotnet test`
- [@Evangelink](https://github.com/Evangelink)
- [@artsmatthewdavis](https://github.com/artsmatthewdavis)
