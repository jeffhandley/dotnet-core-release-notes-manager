# Libraries in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new library features and improvements:

<!-- toc -->

- [System.Text.Json union support](#systemtextjson-union-support)
- [Configurable variable name transformation in EnvironmentVariables configuration](#configurable-variable-name-transformation-in-environmentvariables-configuration)
- [DI: shared singleton instances no longer disposed twice](#di-shared-singleton-instances-no-longer-disposed-twice)
- [ZIP archive improvements](#zip-archive-improvements)
- [DNS hostname null-character validation](#dns-hostname-null-character-validation)
- [`FrozenDictionary` construction is faster](#frozendictionary-construction-is-faster)
- [`AsnEncodedData.RawData` setter obsoleted](#asnencodeddatarawdata-setter-obsoleted)
- [CBOR nesting depth limit (`CborReader` / `CborWriter`)](#cbor-nesting-depth-limit-cborreader--cborwriter)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

.NET Libraries updates in .NET 11:

- [What's new in .NET 11](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-11/libraries)

## System.Text.Json union support

`System.Text.Json` now supports serializing and deserializing C# 14 union types ([dotnet/runtime #128162](https://github.com/dotnet/runtime/pull/128162)). When a union type is used as a property type, parameter type, or return type in a type hierarchy, the serializer handles the discriminated cases automatically — mapping each union case to its underlying representation without requiring custom converters.

This works with both reflection-based and source-generated serialization:

```csharp
[JsonPolymorphic]
union Shape
{
    Circle(double Radius),
    Rectangle(double Width, double Height),
    Triangle(double Base, double Height)
}

// Serialization
Shape shape = new Shape.Circle(5.0);
string json = JsonSerializer.Serialize(shape);
// {"$type":"Circle","Radius":5.0}

// Deserialization
Shape restored = JsonSerializer.Deserialize<Shape>(json);
```

Source-generated serialization with `JsonSerializerContext` also works for union types, providing trim-safe and AOT-compatible serialization for union cases.

## Configurable variable name transformation in EnvironmentVariables configuration

The `EnvironmentVariables` configuration provider now supports a configurable `VariableNameTransformation` delegate ([dotnet/runtime #127503](https://github.com/dotnet/runtime/pull/127503)). By default, the provider converts `__` to `:` to flatten nested configuration keys; custom transformations let you override that mapping.

```csharp
var builder = new ConfigurationBuilder()
    .AddEnvironmentVariables(options =>
    {
        options.VariableNameTransformation = name =>
            name.Replace("__", ":", StringComparison.Ordinal)
                .Replace(".", ":", StringComparison.Ordinal);
    });
```

This is useful for environments where configuration keys use conventions other than double-underscore — for example container environments that prefer dots or single underscores — without needing a custom provider.

## DI: shared singleton instances no longer disposed twice

A correctness fix ensures that singleton instances shared across multiple service descriptors (keyed singletons, open-generic singletons) are disposed only once when the root `IServiceProvider` is disposed ([dotnet/runtime #128768](https://github.com/dotnet/runtime/pull/128768)). Previously, if the same singleton instance appeared in multiple scope-tracking buckets, its `IDisposable.Dispose()` could be called multiple times on teardown, potentially causing resource double-free or `ObjectDisposedException`.

## ZIP archive improvements

### Uncompressed size validated before decompression

`ZipArchiveEntry` now validates the declared uncompressed size against reasonable bounds when opening an entry for update ([dotnet/runtime #128319](https://github.com/dotnet/runtime/pull/128319)). This closes a ZIP bomb vector where a tiny compressed stream claimed an enormous uncompressed size, causing the runtime to pre-allocate gigabytes of memory.

### Mandatory Zip64 extended information fields recognized

The TAR reader now correctly handles mandatory Zip64 Extended Information extra fields that must be present when entry sizes exceed the 32-bit ZIP limit ([dotnet/runtime #129426](https://github.com/dotnet/runtime/pull/129426)). Previously, entries near the 4 GiB boundary could fail to read or report incorrect sizes.

## DNS hostname null-character validation

`Dns.GetHostEntry`, `Dns.GetHostAddresses`, and related APIs now reject hostnames containing embedded null characters (`\0`) ([dotnet/runtime #128982](https://github.com/dotnet/runtime/pull/128982)). Native string functions silently truncate at the first null, which could cause a name like `"evil\0trusted.example.com"` to resolve as `"evil"`. The validation throws `ArgumentException` before the name reaches the resolver.

## `FrozenDictionary` construction is faster

`IEnumerable<T>.ToFrozenDictionary()` now pre-sizes the intermediate mutable dictionary more accurately, reducing allocations and rehashing during the construction phase ([dotnet/runtime #128300](https://github.com/dotnet/runtime/pull/128300)). The benefit is most visible when building `FrozenDictionary` from large enumerables whose count can be determined upfront.

## `AsnEncodedData.RawData` setter obsoleted

The `set` accessor of `AsnEncodedData.RawData` is now marked `[Obsolete]` ([dotnet/runtime #129765](https://github.com/dotnet/runtime/pull/129765)). The setter is difficult to use correctly because it bypasses the object's internal consistency guarantees; callers should reconstruct the `AsnEncodedData` instance from the new raw bytes using the constructor instead.

## CBOR nesting depth limit (`CborReader` / `CborWriter`)

`CborReaderOptions` and `CborWriterOptions` gain a configurable `MaxDepth` property that limits how deeply nested a CBOR value can be during reading or writing ([dotnet/runtime #129273](https://github.com/dotnet/runtime/pull/129273)). Without a depth limit, a malicious or malformed CBOR payload with extreme nesting can exhaust the call stack.

```csharp
// Reader: default max depth is 64; set via options
var options = new CborReaderOptions { MaxDepth = 16 };
var reader = new CborReader(data, options);

// Writer: default max depth is 1000; set via options
var writerOptions = new CborWriterOptions { MaxDepth = 16 };
var writer = new CborWriter(writerOptions);
```

> **Breaking change:** `CborReader` previously had no depth limit. Code that reads CBOR values nested deeper than 64 levels will now throw `CborContentException`. Set `CborReaderOptions.MaxDepth` to a higher value (or `-1` for unlimited) if your data legitimately requires deeper nesting.

## Bug fixes

- **`JsonSchemaExporter`** — No longer drops nullability for nullable floating-point types inside composition schemas ([dotnet/runtime #129530](https://github.com/dotnet/runtime/pull/129530)).
- **`PhysicalFilesWatcher`** — Avoids creating recursive `FileSystemWatcher` instances when the path does not require it ([dotnet/runtime #128072](https://github.com/dotnet/runtime/pull/128072)).
- **`Process.WaitForExit(int)`** — Now validates that the `milliseconds` argument is non-negative ([dotnet/runtime #128563](https://github.com/dotnet/runtime/pull/128563)).
- **Keyed DI services** — Keyed-service probing for built-in DI services (`IServiceProvider`, `IServiceCollection`) is now correct ([dotnet/runtime #128198](https://github.com/dotnet/runtime/pull/128198)).
- **`JsonSchemaExporter`** — Nullable floating-point composition schemas no longer drop nullability annotations ([dotnet/runtime #129530](https://github.com/dotnet/runtime/pull/129530)).

## Community contributors

Thank you contributors! ❤️

- [@dotnet community](https://github.com/dotnet/runtime/pulls?q=is%3Apr+is%3Amerged+label%3Acommunity-contribution)
