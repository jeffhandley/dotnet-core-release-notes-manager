# F# in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes F# improvements:

<!-- toc -->

- [`Array.init` with `InlineIfLambda`](#arrayinit-with-inlineiflambda)
- [Fix: `let _ = &expr` now compiles correctly](#fix-let-_--expr-now-compiles-correctly)
- [Type aliases preserved in `match | null` refinement](#type-aliases-preserved-in-match--null-refinement)
- [Warning for inconsistent `[<CompiledName>]`](#warning-for-inconsistent-compiledname)
- [`for` expression debugging improvements](#for-expression-debugging-improvements)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## `Array.init` with `InlineIfLambda`

`Array.init` is now annotated with `[<InlineIfLambda>]` ([dotnet/fsharp #19869](https://github.com/dotnet/fsharp/pull/19869)). When the initializer is a lambda, the compiler inlines it directly, eliminating the delegate allocation and dispatch overhead. Tight loops that call `Array.init` with a lambda initializer now generate code comparable to a hand-written loop.

```fsharp
// Before: initializer allocated as a delegate object
let a = Array.init 1000 (fun i -> i * 2)

// After: same syntax; lambda inlined — no allocation, faster code
let a = Array.init 1000 (fun i -> i * 2)
```

## Fix: `let _ = &expr` now compiles correctly

`let _ = &expr` previously failed to compile even though `let x = &expr` worked ([dotnet/fsharp #19811](https://github.com/dotnet/fsharp/pull/19811)). The discard pattern `_` in a `let` binding is now treated consistently with a named binding when the right-hand side is a ref expression.

```fsharp
let mutable v = 42
let _ = &v  // now compiles; previously a compiler error
```

## Type aliases preserved in `match | null` refinement

When a `match` expression has a `| null` case, the F# compiler now preserves type aliases in the non-null branches ([dotnet/fsharp #19745](https://github.com/dotnet/fsharp/pull/19745)). Previously the alias was erased to its underlying type, producing less readable type inference errors and hover information.

```fsharp
type MyList = int list

let describe (x: MyList | null) =
    match x with
    | null -> "null"
    | list -> list  // type is inferred as MyList, not int list
```

## Warning for inconsistent `[<CompiledName>]`

F# now emits a warning when extension overloads in the same type have inconsistent `[<CompiledName>]` attributes ([dotnet/fsharp #19737](https://github.com/dotnet/fsharp/pull/19737)). Inconsistent compiled names produce unexpected bindings when the type is consumed from C# or VB.NET. The warning surfaces during compilation, letting you fix the mismatch before it reaches callers.

## `for` expression debugging improvements

The debugger stepping experience for `for` expressions has been reworked ([dotnet/fsharp #19894](https://github.com/dotnet/fsharp/pull/19894)). Step-over and step-into now move through `for` loop iterations more predictably, without jumping to unexpected source locations in the generated IL sequence points.

## Community contributors

Thank you contributors! ❤️

- [@vzarytovskii](https://github.com/dotnet/fsharp/pulls?q=is%3Apr+is%3Amerged+author%3Avzarytovskii)
- [@KevinRansom](https://github.com/dotnet/fsharp/pulls?q=is%3Apr+is%3Amerged+author%3AKevinRansom)
