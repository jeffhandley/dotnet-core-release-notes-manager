# .NET SDK in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new .NET SDK features & enhancements:

<!-- toc -->

- [`dotnet new mcpserver` project template](#dotnet-new-mcpserver-project-template)
- [File-based apps: `#:include .dll` support](#file-based-apps-include-dll-support)
- [Multi-arch container images with Podman](#multi-arch-container-images-with-podman)
- [Blazor WASM diagnostics defaults](#blazor-wasm-diagnostics-defaults)
- [OpenTelemetry OTLP environment variable support](#opentelemetry-otlp-environment-variable-support)
- [OTel for AOT operations](#otel-for-aot-operations)
- [Improved empty `TargetFramework` diagnostic (NETSDK1241)](#improved-empty-targetframework-diagnostic-netsdk1241)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## `dotnet new mcpserver` project template

A new `mcpserver` project template is bundled with the .NET 11 SDK ([dotnet/sdk #54132](https://github.com/dotnet/sdk/pull/54132)). Run `dotnet new mcpserver` to scaffold a Model Context Protocol server project wired to the `Microsoft.Extensions.AI` hosting model.

```bash
dotnet new mcpserver -n MyTools
cd MyTools
dotnet run
```

The generated project includes an example tool, service registration via `IServiceCollection`, and the standard `IHost` run loop. You can extend it by adding `[McpTool]`-annotated methods to the tool class.

## File-based apps: `#:include .dll` support

File-based apps (single-file `.cs` scripts) now support `#:include .dll` directives by default ([dotnet/sdk #54396](https://github.com/dotnet/sdk/pull/54396)). This lets a script reference a local assembly directly without creating a project file.

```csharp
#:include path/to/MyLibrary.dll
#:sdk Microsoft.NET.Sdk

using MyLibrary;

var result = MyLibrary.SomeClass.DoWork();
Console.WriteLine(result);
```

Previously you had to reference NuGet packages or set up a full project. With `#:include .dll` you can now consume locally built or pre-existing assemblies in a one-file workflow.

## Multi-arch container images with Podman

`dotnet publish` container publishing now supports building multi-architecture images when Podman is the container engine ([dotnet/sdk #54575](https://github.com/dotnet/sdk/pull/54575)). Set `ContainerArchitectures` to the architectures you want and the SDK invokes `buildah manifest` to produce a multi-arch manifest list:

```xml
<PropertyGroup>
  <ContainerArchitectures>linux/amd64;linux/arm64</ContainerArchitectures>
</PropertyGroup>
```

```bash
dotnet publish --os linux -p:ContainerArchitectures="linux/amd64;linux/arm64"
```

This matches the existing Docker multi-arch behavior and works with both rootful and rootless Podman setups.

## Blazor WASM diagnostics defaults

Two Blazor WebAssembly diagnostics support properties now default to `true` ([dotnet/sdk #54824](https://github.com/dotnet/sdk/pull/54824)):

- `BlazorWebAssemblyEnableDebugging`
- `BlazorWebAssemblyEnableProfiling`

These properties enable the browser debugging bridge and profiling infrastructure at publish time. You no longer have to opt in manually for browser-attached debugging or the WebAssembly performance trace API.

## OpenTelemetry OTLP environment variable support

The .NET SDK now respects the standard [OpenTelemetry OTLP environment variables](https://opentelemetry.io/docs/specs/otel/protocol/exporter/) for enabling exporters ([dotnet/sdk #54386](https://github.com/dotnet/sdk/pull/54386)). When `OTEL_EXPORTER_OTLP_ENDPOINT` or the per-signal variants are set, the SDK automatically activates the OTLP exporter without requiring any code change.

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
dotnet run   # SDK telemetry now exported via OTLP
```

## OTel for AOT operations

OpenTelemetry telemetry now works for SDK operations that run in an AOT (ahead-of-time compiled) context ([dotnet/sdk #54544](https://github.com/dotnet/sdk/pull/54544)). Previously, OTel instrumentation was silently skipped when the SDK ran AOT phases. With this change, build traces and metrics are emitted throughout the full publish pipeline, including NativeAOT publish.

## Improved empty `TargetFramework` diagnostic (NETSDK1241)

When a project is missing a `<TargetFramework>` element, the SDK now emits a dedicated `NETSDK1241` error with a clear actionable message instead of the generic missing-property error ([dotnet/sdk #54335](https://github.com/dotnet/sdk/pull/54335)):

```text
error NETSDK1241: TargetFramework is required. Add <TargetFramework>net11.0</TargetFramework>
to your project file, or use a .NET SDK with a known default TargetFramework.
```

## Community contributors

Thank you contributors! ❤️

- [@baronfel](https://github.com/dotnet/sdk/pulls?q=is%3Apr+is%3Amerged+author%3Abaronfel)
- [@Daviiduhh](https://github.com/dotnet/sdk/pulls?q=is%3Apr+is%3Amerged+author%3ADaviiduhh)
