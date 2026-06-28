# C# in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes the following C# language and compiler updates:

<!-- toc -->

- [Extension indexers](#extension-indexers)
- [Labeled `break` and `continue`](#labeled-break-and-continue)
- [`RegisterPreCompilationSourceOutput` for incremental generators](#registerprecompilationsourceoutput-for-incremental-generators)
- [Union type constructor accessibility](#union-type-constructor-accessibility)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

C# updates:

- [What's new in C# 14](https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-14)

## Extension indexers

> This is a preview feature for .NET 11.

C# 14 extension members now support indexers, completing the last major gap in the extension-member design. Extension indexers let you define `this[...]` accessors on any type — including types you don't own — without requiring inheritance or wrapper types ([dotnet/roslyn #81607](https://github.com/dotnet/roslyn/pull/81607)).

```csharp
extension StringExtensions for string
{
    public char this[Index index] => this[index.IsFromEnd ? Length - index.Value : index.Value];
    public string this[Range range] => Substring(range.Start.GetOffset(Length), range.End.GetOffset(Length) - range.Start.GetOffset(Length));
}

string s = "hello world";
char c = s[^1];          // 'd' via extension indexer
string sub = s[1..5];    // "ello" via extension range indexer
```

Preview 6 includes substantial coverage work across the feature:

- **Nullability analysis** — The compiler now enforces nullable reference type annotations on extension indexer receivers and return types ([dotnet/roslyn #81971](https://github.com/dotnet/roslyn/pull/81971)).
- **`dynamic` arguments rejected** — Indexers with `dynamic` arguments produce an error, matching the limitation on regular dynamic indexing ([dotnet/roslyn #82220](https://github.com/dotnet/roslyn/pull/82220)).
- **Implicit indexers (`^` and `..`)** — Extension indexers that accept `Index` or `Range` are now recognized as implicit indexers, enabling `^n` and `a..b` syntax ([dotnet/roslyn #82453](https://github.com/dotnet/roslyn/pull/82453)).
- **Implicit indexers in list-patterns** — `^n` patterns and slice patterns work through extension indexers ([dotnet/roslyn #82757](https://github.com/dotnet/roslyn/pull/82757)).
- **Classic extension `Slice` method** — A static extension `Slice(int, int)` method can serve as the range backing for a type, consistent with how built-in range support works ([dotnet/roslyn #82836](https://github.com/dotnet/roslyn/pull/82836)).
- **`string` and array scenarios** — Extension indexers on `string` and array types work correctly including existing special-case paths ([dotnet/roslyn #83041](https://github.com/dotnet/roslyn/pull/83041)).
- **Compound assignment** — `++`, `--`, and `op=` compound assignment through extension indexers all produce correct receiver-handling code ([dotnet/roslyn #83553](https://github.com/dotnet/roslyn/pull/83553), [dotnet/roslyn #83587](https://github.com/dotnet/roslyn/pull/83587)).

## Labeled `break` and `continue`

> This is a preview feature for .NET 11.

C# 14 adds labeled `break` and `continue` statements for exiting or continuing an outer loop from within a nested loop, without needing a flag variable or a `goto` ([dotnet/roslyn #83197](https://github.com/dotnet/roslyn/pull/83197)):

```csharp
outer: foreach (var row in grid)
{
    foreach (var cell in row)
    {
        if (cell.HasError)
            break outer;   // exits the outer foreach immediately
        Process(cell);
    }
}
```

Labels follow the same scoping rules as existing C# labels and are only valid on loop statements (`for`, `foreach`, `while`, `do`). Preview 6 completes the core implementation: binding, lowering, IL emit, and semantic model are now all in place ([dotnet/roslyn #83198](https://github.com/dotnet/roslyn/pull/83198)).

### Analyzer and fixer: prefer labeled `break`/`continue` over `goto` and flag variables

A new Roslyn analyzer detects patterns where a labeled `break` or `continue` can replace a `goto`-based loop-exit or a boolean flag variable, and offers a code fix to apply the rewrite automatically ([dotnet/roslyn #84170](https://github.com/dotnet/roslyn/pull/84170)). For example:

```csharp
// Before: using a flag variable
bool found = false;
foreach (var row in grid)
{
    foreach (var cell in row)
    {
        if (cell.HasError) { found = true; break; }
        Process(cell);
    }
    if (found) break;
}

// After: labeled break (applied by the fixer)
outer: foreach (var row in grid)
{
    foreach (var cell in row)
    {
        if (cell.HasError) break outer;
        Process(cell);
    }
}
```

The analyzer runs in IDEs and during `dotnet build`, surfacing suggestions for both `goto`-based exits and flag-variable patterns.

## `RegisterPreCompilationSourceOutput` for incremental generators

Incremental source generators can now register a `RegisterPreCompilationSourceOutput` step that runs before the compilation's syntax trees are produced ([dotnet/roslyn #83088](https://github.com/dotnet/roslyn/pull/83088)). Pre-compilation outputs are useful for generating source files that other generators or the compiler itself need to see during its initial type resolution pass — previously, a generator that produced types consumed by another generator required multiple compilation rounds or workarounds.

```csharp
context.RegisterPreCompilationSourceOutput(ctx =>
{
    // Add source before compilation starts
    ctx.AddSource("GeneratedTypes.g.cs", SourceText.From("""
        namespace Generated { public class EarlyType { } }
        """, Encoding.UTF8));
});
```

## Union type constructor accessibility

Union declarations can now include non-public constructors with a single parameter ([dotnet/roslyn #83788](https://github.com/dotnet/roslyn/pull/83788)). This allows union cases to have `internal` or `protected internal` constructors while still being publicly visible through the union type, enabling more controlled construction patterns from within the same assembly.

## Bug fixes

- **Compiler** — Fixed colorization of type names when a static member access uses a qualified generic type name (e.g., `MyType<Qualified.Name>.StaticMember`) in IDE tooling ([dotnet/roslyn #83781](https://github.com/dotnet/roslyn/pull/83781)).
- **Hot Reload** — The `_disabled` flag is now reset when a new debug session starts, so Hot Reload works again after stopping and re-launching the debugger ([dotnet/roslyn #83747](https://github.com/dotnet/roslyn/pull/83747)).
- **Semantic tokens** — Full semantic tokens support added to Razor files in language server scenarios ([dotnet/roslyn #83800](https://github.com/dotnet/roslyn/pull/83800)).

## Community contributors

Thank you contributors! ❤️

- [@DoctorKrolic](https://github.com/DoctorKrolic)
- [@dusrdev](https://github.com/dusrdev)
- [@Thomas-Shephard](https://github.com/Thomas-Shephard)
- [@bernd5](https://github.com/bernd5)
