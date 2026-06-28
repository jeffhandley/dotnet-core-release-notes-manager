# Announcing .NET 11 Preview 6

.NET 11 Preview 6 is available today. This preview focuses on **C# 14 language completeness**, a significant **Blazor WebAssembly out-of-process renderer**, and continued depth across the stack — from new **System.Text.Json union support**, a bundled **MCP server template**, and **FULL OUTER JOIN** in EF Core, to security improvements in the runtime and async infrastructure work.

## What's new

- [.NET Runtime](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/runtime.md) — ARM64 PAC-RET JIT security, in-process crash reporting, SIMD lane APIs, and Stream wrappers for memory types
- [.NET Libraries](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/libraries.md#systemtextjson-union-support) — System.Text.Json union support, configurable EnvironmentVariables name transformation, DI singleton disposal fix
- [ASP.NET Core](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/aspnetcore.md) — [Blazor WASM Out-of-Process Renderer](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/aspnetcore.md#blazor-webassembly-out-of-process-renderer), [SupplyParameterFromSession](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/aspnetcore.md#supplyparameterfromsession-for-blazor), [OpenAPI 3.2 default](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/aspnetcore.md#openapi-32-is-now-the-default), SignalR auth refresh, CSRF via Fetch Metadata
- [C#](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/csharp.md) — [Extension indexers](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/csharp.md#extension-indexers) matured with nullability, compound assignment, and string/array coverage; [labeled break/continue](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/csharp.md#labeled-break-and-continue)
- [F#](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/fsharp.md) — Array.init InlineIfLambda, double-dispose fix, improved debugger stepping for `for` expressions
- [EF Core](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/efcore.md) — [FULL OUTER JOIN support](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/efcore.md#full-outer-join-support), SQL Server JSON indexes, EF1003 raw SQL injection analyzer
- [SDK & Tooling](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/sdk.md) — [MCP server project template](https://github.com/dotnet/core/blob/main/release-notes/11.0/preview/preview6/sdk.md#mcp-server-project-template-bundled-with-the-sdk), `dotnet test --no-dependencies`, improved `dotnet watch` diagnostics

## Highlights

### Blazor WebAssembly Out-of-Process Renderer

Blazor WASM can now render components on a dedicated WebAssembly thread, freeing the browser's main thread for input and animations. This is the foundational piece for multi-threaded Blazor apps and directly addresses responsiveness complaints in render-heavy UIs. Enable it via the new `BrowserOptions` API.

### C# extension indexers reach feature completeness

Extension indexers in C# 14 now support nullability analysis, dynamic-argument restrictions, implicit indexer syntax (`^n` and `a..b`), list patterns, compound assignment, and string/array scenarios. The `RegisterPreCompilationSourceOutput` API also landed for incremental source generators, and labeled `break`/`continue` has parsing support.

### System.Text.Json union support

Union types declared with C# 14's `union` keyword are now first-class in `System.Text.Json` — both reflection and source-generated modes. This closes the loop on the full serialization story for unions.

### MCP server template in the SDK

`dotnet new mcpserver` is now bundled with the SDK, providing a ready-to-run scaffold for MCP (Model Context Protocol) servers. Combined with the existing `mcpclient` template, you can scaffold a full MCP client–server pair from the CLI.

### EF Core FULL OUTER JOIN

EF Core 11 now translates LINQ queries that require a full outer join, one of the most commonly requested EF Core LINQ features. Combined with the new EF1003 analyzer (detects `string.Format` in raw SQL APIs), SQL Server JSON index support, and wildcard `*` migration commands, this is a solid EF Core preview.

## Get started

Download [.NET 11 Preview 6](https://dotnet.microsoft.com/download/dotnet/11.0) and try the new features.

Share your feedback:

- [dotnet/runtime issues](https://github.com/dotnet/runtime/issues) for runtime and libraries
- [dotnet/aspnetcore issues](https://github.com/dotnet/aspnetcore/issues) for ASP.NET Core
- [dotnet/roslyn issues](https://github.com/dotnet/roslyn/issues) for C# language and compiler
- [dotnet/efcore issues](https://github.com/dotnet/efcore/issues) for Entity Framework Core
