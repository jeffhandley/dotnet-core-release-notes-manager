# C# in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new C# 14 features & enhancements:

<!-- toc -->

- [Extension indexers](#extension-indexers)
- [Labeled `break` and `continue`](#labeled-break-and-continue)
- [Union improvements](#union-improvements)
- [Unsafe Evolution: `unsafe` fields](#unsafe-evolution-unsafe-fields)
- [`RegisterPreCompilationSourceOutput` for incremental generators](#registerprecompilationsourceoutput-for-incremental-generators)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## Extension indexers

Extension blocks in C# 14 now support indexers ([dotnet/roslyn #81607](https://github.com/dotnet/roslyn/pull/81607)). Extension indexers let you add `this[index]` syntax to types you don't own, matching the full range of scenarios available for instance indexers.

```csharp
public static class SparseExtensions
{
    extension(int[] source)
    {
        public int this[Index index] => source[index.GetOffset(source.Length)];
        public int[] this[Range range] => source[range];
    }
}

int[] data = [10, 20, 30, 40];
Console.WriteLine(data[^1]);          // 40 — uses extension indexer
Console.WriteLine(data[1..3].Length); // 2  — uses extension range indexer
```

This milestone delivers the core scenarios for extension indexers:

- Nullability analysis for extension indexers ([dotnet/roslyn #81971](https://github.com/dotnet/roslyn/pull/81971))
- Dynamic arguments are disallowed ([dotnet/roslyn #82220](https://github.com/dotnet/roslyn/pull/82220))
- Implicit indexers work inside list-patterns ([dotnet/roslyn #82757](https://github.com/dotnet/roslyn/pull/82757))
- Classic extension `Slice` methods are recognized ([dotnet/roslyn #82836](https://github.com/dotnet/roslyn/pull/82836))

## Labeled `break` and `continue`

C# 14 adds syntax and parsing support for labeled `break` and `continue` statements ([dotnet/roslyn #83197](https://github.com/dotnet/roslyn/pull/83197)). Labeled jumps let you exit or continue a specific outer loop from inside a nested loop without introducing a flag variable.

```csharp
outer:
for (int i = 0; i < 10; i++)
{
    for (int j = 0; j < 10; j++)
    {
        if (condition) break outer;    // exits the outer loop
        if (other)    continue outer; // continues the outer loop's next iteration
    }
}
```

> This is a preview feature for .NET 11. The syntax is available in C# 14 preview; semantics and emission continue to be refined in subsequent previews.

## Union improvements

Discriminated union declarations receive several improvements this preview:

**Non-public single-parameter constructors are now allowed** ([dotnet/roslyn #83788](https://github.com/dotnet/roslyn/pull/83788)). A union member can use a non-public constructor with a single parameter to represent a typed case, enabling cleaner encapsulation:

```csharp
union Shape
{
    Circle(float radius);
    Rectangle(float width, float height);
    Point;          // valueless case
}
```

**`not` patterns apply to the incoming value** ([dotnet/roslyn #83904](https://github.com/dotnet/roslyn/pull/83904)). A `not` pattern inside a union switch now matches against the union itself rather than the active case. This aligns with the expected semantics: `not Circle` matches any `Shape` that is not a `Circle`.

**Custom union declarations require a minimal API set** ([dotnet/roslyn #83813](https://github.com/dotnet/roslyn/pull/83813)). Unions that supply a custom `IUnionValue` provider must implement a required minimal surface; the compiler now reports an error when the surface is incomplete.

**Provider interface disallowed on union declarations** ([dotnet/roslyn #83815](https://github.com/dotnet/roslyn/pull/83815)). A union declaration cannot directly implement the member-provider interface; only the generated internal implementation may implement it.

## Unsafe Evolution: `unsafe` fields

> Unsafe Evolution remains a preview feature in .NET 11.

C# 14 adds `unsafe` fields, enabling structs to contain pointer-typed fields without marking the entire struct `unsafe` ([dotnet/roslyn #83694](https://github.com/dotnet/roslyn/pull/83694)):

```csharp
struct UnsafeWrapper
{
    unsafe int* ptr;   // field-level unsafe; no need for `unsafe struct`

    public void Set(int* p)
    {
        unsafe { ptr = p; }
    }
}
```

`unsafe` fields can only be read or written inside an `unsafe` block; all other access (reflection, serialization) continues to treat them as a normal field.

## `RegisterPreCompilationSourceOutput` for incremental generators

A new `RegisterPreCompilationSourceOutput` API is available on `IncrementalGeneratorInitializationContext` ([dotnet/roslyn #83088](https://github.com/dotnet/roslyn/pull/83088)). Source added via this callback runs before the main compilation phase, allowing generated code to influence symbol resolution and avoid the ordering problems that arise when a generator depends on symbols from its own output.

```csharp
context.RegisterPreCompilationSourceOutput(ctx =>
{
    ctx.AddSource("GeneratedTypes.g.cs", SourceText.From(source, Encoding.UTF8));
});
```

## Community contributors

Thank you contributors! ❤️

- [@bernd5](https://github.com/dotnet/roslyn/pulls?q=is%3Apr+is%3Amerged+author%3Abernd5)
