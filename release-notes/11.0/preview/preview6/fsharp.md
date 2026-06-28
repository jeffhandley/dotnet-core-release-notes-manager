# F# in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes the following F# language and compiler updates:

<!-- toc -->

- [`Array.init` is now `InlineIfLambda`](#arrayinit-is-now-inlineiflambda)
- [Fix: double `Dispose` in `use` bindings with `as` patterns](#fix-double-dispose-in-use-bindings-with-as-patterns)
- [Debugger: reworked `for` expression stepping](#debugger-reworked-for-expression-stepping)
- [Warning for inconsistent `[<CompiledName>]` across extension overloads](#warning-for-inconsistent-compiledname-across-extension-overloads)
- [Warning FS3888: consumer-visible attributes missing from `.fsi` signatures](#warning-fs3888-consumer-visible-attributes-missing-from-fsi-signatures)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

F# updates:

- [What's new in F# 9](https://learn.microsoft.com/dotnet/fsharp/whats-new/fsharp-9)

## `Array.init` is now `InlineIfLambda`

`Array.init` is now annotated with `[<InlineIfLambda>]`, which instructs the F# compiler to inline the initializer function directly into the generated loop when it is passed as a lambda ([dotnet/fsharp #19869](https://github.com/dotnet/fsharp/pull/19869)):

```fsharp
// The lambda is inlined; no delegate allocation, no indirect call
let squares = Array.init 1000 (fun i -> i * i)
```

For performance-sensitive initialization code — particularly in inner loops or hot paths — this eliminates the overhead of a delegate allocation and indirect function call. The change is compatible: any valid `Array.init` call benefits automatically without source changes.

## Fix: double `Dispose` in `use` bindings with `as` patterns

A correctness bug in `use x as y = expr` bindings has been fixed: the resource was being disposed twice — once when `x` went out of scope and once when `y` went out of scope, even though both names referred to the same object ([dotnet/fsharp #19858](https://github.com/dotnet/fsharp/pull/19858)). The fix ensures that exactly one disposal happens at the scope exit. Code that relied on the double-dispose (rare, and almost certainly unintentional) will behave differently; all other code is unaffected.

## Debugger: reworked `for` expression stepping

Stepping through `for` expressions in the F# debugger has been reworked ([dotnet/fsharp #19894](https://github.com/dotnet/fsharp/pull/19894)). Previously, single-step navigation through `for i in collection do` loops produced redundant or confusingly placed breakpoints, particularly for comprehensions and sequences. The new debug-point emission positions breakpoints at the loop head and body consistently, matching the expected stepping behavior for range-based and enumerable-based loops.

## Warning for inconsistent `[<CompiledName>]` across extension overloads

A new warning fires when extension method overloads in the same scope have inconsistent `[<CompiledName>]` attributes ([dotnet/fsharp #19737](https://github.com/dotnet/fsharp/pull/19737)). Inconsistent compiled names mean that some overloads get different names in the IL output, which can break C# callers or reflection-based code that expects a uniform name for all overloads of the same method.

```fsharp
type Foo with
    [<CompiledName("Bar")>]
    member _.DoThing(x: int) = ()

    // Warning: CompiledName "Baz" differs from "Bar" on the other overload
    [<CompiledName("Baz")>]
    member _.DoThing(x: string) = ()
```

## Warning FS3888: consumer-visible attributes missing from `.fsi` signatures

A new warning, FS3888, fires when a declaration in a `.fs` file has an attribute that is visible to consumers but the corresponding `.fsi` signature omits that attribute ([dotnet/fsharp #19880](https://github.com/dotnet/fsharp/pull/19880)). Consumer-visible attributes — `[<Obsolete>]`, `[<Extension>]`, `[<AttributeUsage>]`, and similar — affect how callers interact with the symbol; omitting them from the signature means the public API surface is incomplete. This warning encourages explicit, consistent signatures.

## Bug fixes

- **`use` bindings** — Type aliases are now preserved when narrowing in a `match expr with | null -> ...` pattern, preventing unnecessary re-expansion of the alias ([dotnet/fsharp #19745](https://github.com/dotnet/fsharp/pull/19745)).
- **SRTP** — `get_Item` witness resolution for `string` indexers now works correctly in SRTP constraints ([dotnet/fsharp #19757](https://github.com/dotnet/fsharp/pull/19757)).
- **FSI** — NuGet restore output is suppressed under `dotnet fsi --quiet` as expected ([dotnet/fsharp #19808](https://github.com/dotnet/fsharp/pull/19808)).
- **Quotations** — Empty-string match lowering no longer leaks into the AST when used inside a quotation ([dotnet/fsharp #19923](https://github.com/dotnet/fsharp/pull/19923)).
- **Realsig** — Fixed degraded codegen for inner recursive functions under `--realsig+` ([dotnet/fsharp #19882](https://github.com/dotnet/fsharp/pull/19882)).
- **XmlDoc** — Validation for get/set property pair XML docs now works correctly ([dotnet/fsharp #19884](https://github.com/dotnet/fsharp/pull/19884)).
- **Editor diagnostics** — Duplicate editor diagnostics caused by a Roslyn workaround have been removed ([dotnet/fsharp #19812](https://github.com/dotnet/fsharp/pull/19812)).
- **Reference assemblies** — Non-deterministic MVIDs in reference assemblies are fixed ([dotnet/fsharp #19801](https://github.com/dotnet/fsharp/pull/19801)).

## Community contributors

Thank you contributors! ❤️

- [@brianrourkeboll](https://github.com/brianrourkeboll)
- [@vzarytovskii](https://github.com/vzarytovskii)
- [@edgarfgp](https://github.com/edgarfgp)
- [@abelbraaksma](https://github.com/abelbraaksma)
