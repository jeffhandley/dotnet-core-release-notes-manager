# Libraries in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new Libraries features & enhancements:

<!-- toc -->

- [`System.Text.Json` union type support](#systemtextjson-union-type-support)
- [Stream wrappers for memory and text-based types](#stream-wrappers-for-memory-and-text-based-types)
- [Configurable environment variable name transformation](#configurable-environment-variable-name-transformation)
- [Improved `WebSocket` exceptions](#improved-websocket-exceptions)
- [`Math.BigMul` faster on x64](#mathbigmul-faster-on-x64)
- [`IsClosedTypeAttribute` gains `DerivedTypes`](#isclosedtypeattribute-gains-derivedtypes)
- [Breaking changes](#breaking-changes)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## `System.Text.Json` union type support

`System.Text.Json` now supports serializing and deserializing C# 14 union types ([dotnet/runtime #128162](https://github.com/dotnet/runtime/pull/128162)). Union types are represented in JSON using a discriminator field. The serializer recognizes union declarations attributed with the new union discriminator attribute and produces correct type-discriminated JSON without any additional configuration.

```csharp
[JsonPolymorphic]
[JsonDerivedType(typeof(Cat), "cat")]
[JsonDerivedType(typeof(Dog), "dog")]
public abstract class Animal { }

public class Cat : Animal { public string Name { get; set; } = ""; }
public class Dog : Animal { public string Name { get; set; } = ""; }
```

## Stream wrappers for memory and text-based types

New `Stream` wrappers are available for in-memory and text-based types ([dotnet/runtime #129811](https://github.com/dotnet/runtime/pull/129811)). These wrappers let you pass memory or text data to APIs that expect a `Stream` without allocating intermediate byte arrays.

<!-- TODO: Confirm the exact API surface (e.g. MemoryStream<T> wrapper, ReadOnlySequence<byte> stream, TextReader/TextWriter stream) once API diff is available. -->

## Configurable environment variable name transformation

`EnvironmentVariablesConfigurationSource` now supports a configurable `VariableNameTransformation` ([dotnet/runtime #127503](https://github.com/dotnet/runtime/pull/127503)). Applications that follow naming conventions other than the default double-underscore hierarchy separator (such as `SCREAMING_SNAKE_CASE`) can supply a custom transformation, eliminating the need for hand-written preprocessing.

```csharp
builder.Configuration.AddEnvironmentVariables(opts =>
{
    opts.VariableNameTransformation = name =>
        name.Replace("APP_", "").Replace("_", ":");
});
```

## Improved `WebSocket` exceptions

`WebSocket` exceptions now include informative messages with connection details and error context ([dotnet/runtime #129428](https://github.com/dotnet/runtime/pull/129428)). Previously, exceptions from a failed WebSocket connection provided little information beyond a bare error code. The improved messages make diagnosing WebSocket failures significantly easier.

## `Math.BigMul` faster on x64

`Math.BigMul(long, long, out long)` now emits a hardware `MUL` instruction on x64 instead of calling a software multiplication routine ([dotnet/runtime #117261](https://github.com/dotnet/runtime/pull/117261)). Microbenchmarks show approximately 3× throughput improvement for code that calls `BigMul` in a tight loop.

## `IsClosedTypeAttribute` gains `DerivedTypes`

`IsClosedTypeAttribute` now exposes a `DerivedTypes` property that lists the types the closed hierarchy is sealed to ([dotnet/runtime #129529](https://github.com/dotnet/runtime/pull/129529)). This property complements the C# 14 closed type hierarchy feature and is used by pattern-matching and switch exhaustiveness analysis.

```csharp
[IsClosedType]
[JsonDerivedType(typeof(Cat))]
[JsonDerivedType(typeof(Dog))]
public abstract class Animal { }
```

## Breaking changes

- **`AsnEncodedData.RawData` setter obsoleted** — The `set` accessor is obsoleted ([dotnet/runtime #129765](https://github.com/dotnet/runtime/pull/129765)). Construct a new `AsnEncodedData` instance rather than assigning to the property. The setter will be removed in a future release.
- **TAR reader rejects negative PAX size values** — TAR entries with a negative declared size are now rejected ([dotnet/runtime #128368](https://github.com/dotnet/runtime/pull/128368)). Well-formed archives are unaffected.
- **ZIP update mode validates size up front** — `ZipArchiveEntry` update mode validates the declared uncompressed size before writing ([dotnet/runtime #128319](https://github.com/dotnet/runtime/pull/128319)). Inconsistent archives that previously succeeded will now throw.
- **DNS rejects hostnames with embedded null characters** — `Dns` now rejects hostnames containing null characters ([dotnet/runtime #128982](https://github.com/dotnet/runtime/pull/128982)).

<!-- Filtered features (significant engineering work, but too niche for release notes):
  - COM IidParameterIndex fix (#128214, #128364): Bug fix for COM source-gen, not a new feature. Routes to bug fixes section in runtime.md.
  - PhysicalFilesWatcher recursive avoidance (#128072): Internal perf fix for FileSystemWatcher; no API change.
  - Keyed-service probing fix (#128198): Bug fix for DI; routes to breaking changes since behavior changes.
-->

## Bug fixes

- **System.Text.Json**
  - Fixed `JsonSchemaExporter` dropping nullability for nullable floating-point composition schemas ([dotnet/runtime #129530](https://github.com/dotnet/runtime/pull/129530))
- **System.Net.Http / HTTP**
  - Improved TCP/UDP connection buffer allocation ([dotnet/runtime #128551](https://github.com/dotnet/runtime/pull/128551))
- **Dependency Injection**
  - Shared singleton instances are no longer disposed twice during container teardown ([dotnet/runtime #128768](https://github.com/dotnet/runtime/pull/128768))
  - Keyed services now probe built-in DI services correctly ([dotnet/runtime #128198](https://github.com/dotnet/runtime/pull/128198))
- **Diagnostics / Tracing**
  - Fixed W3C Trace Context Level 2 compliance in the W3C propagator ([dotnet/runtime #129414](https://github.com/dotnet/runtime/pull/129414))
- **System.IO.Compression**
  - Fixed compiled/source-generated lazy loop stack unwinding in Regex ([dotnet/runtime #129628](https://github.com/dotnet/runtime/pull/129628))
  - Fixed COM weak-handle defensive copy in `ReferenceTrackerNativeObjectWrapper` ([dotnet/runtime #129668](https://github.com/dotnet/runtime/pull/129668))
- **System.Threading.RateLimiting**
  - Fixed `NoopLimiter` disposal in `DefaultPartitionedRateLimiter` heartbeat ([dotnet/runtime #127582](https://github.com/dotnet/runtime/pull/127582))

## Community contributors

Thank you contributors! ❤️

- [@MichalPetryka](https://github.com/dotnet/runtime/pulls?q=is%3Apr+is%3Amerged+author%3AMichalPetryka)
