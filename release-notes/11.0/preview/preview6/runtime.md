# .NET Runtime in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new runtime features and performance work:

<!-- toc -->

- [ARM64 Pointer Authentication (PAC-RET) JIT support](#arm64-pointer-authentication-pac-ret-jit-support)
- [Runtime-async: sync task-returning methods get async variants](#runtime-async-sync-task-returning-methods-get-async-variants)
- [CoreCLR interpreter: computed goto dispatch](#coreclr-interpreter-computed-goto-dispatch)
- [Lane construction and composition APIs for SIMD vectors](#lane-construction-and-composition-apis-for-simd-vectors)
- [Stream wrappers for memory and text-based types](#stream-wrappers-for-memory-and-text-based-types)
- [JIT optimizations](#jit-optimizations)
- [Improved `Math.BigMul` performance on x64](#improved-mathbigmul-performance-on-x64)
- [OpenBSD platform improvements](#openbsd-platform-improvements)
- [Security and correctness improvements](#security-and-correctness-improvements)
- [In-process crash report logging](#in-process-crash-report-logging)
- [Breaking changes](#breaking-changes)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

.NET Runtime updates in .NET 11:

- [What's new in .NET 11 runtime](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-11/runtime)

## ARM64 Pointer Authentication (PAC-RET) JIT support

The JIT compiler now emits pointer authentication instructions on ARM64 hardware that supports Pointer Authentication Code (PAC) ([dotnet/runtime #127838](https://github.com/dotnet/runtime/pull/127838)). The PAC-RET (`pacia`/`autia`) instructions authenticate the return address on function entry and exit, providing hardware-enforced mitigation against return-oriented programming (ROP) attacks. This is enabled automatically when the hardware and OS support it — no code changes are required.

The feature targets Arm64 processors with the FEAT_PAUTH extension and operating systems that opt in to PAC (Linux 5.18+, Windows 11 24H2+, macOS 14+). On hardware that does not support PAC, the instructions are NOPs and there is no cost.

## Runtime-async: sync task-returning methods get async variants

> This is a preview feature for .NET 11.

Building on the runtime-async work shipped in earlier previews, the runtime now compiles async variants of synchronous task-returning methods ([dotnet/runtime #128384](https://github.com/dotnet/runtime/pull/128384)). When the JIT encounters a method that returns `Task` or `ValueTask` synchronously (no `await`), it now emits a companion stub that implements the async calling convention directly, avoiding the overhead of the state machine wrapper in the synchronous-completion fast path.

This extends the runtime-async coverage already in place for explicitly `async` methods — the same resumption and continuation machinery is now shared by sync-return variants.

## CoreCLR interpreter: computed goto dispatch

The CoreCLR interpreter now uses computed goto dispatch instead of a traditional `switch` statement for opcode dispatch ([dotnet/runtime #129216](https://github.com/dotnet/runtime/pull/129216)). Computed goto dispatch builds a table of label addresses and jumps directly to each opcode handler, eliminating the branch-table overhead and enabling tighter opcode loops. The result is a significant throughput improvement for interpreted code paths, particularly visible in scenarios where CrossGen2/ReadyToRun is not in use.

## Lane construction and composition APIs for SIMD vectors

New Vector lane construction and composition APIs are available for working with SIMD types at lane granularity ([dotnet/runtime #129627](https://github.com/dotnet/runtime/pull/129627)). The new methods let you create a vector from scalar lane values, extract individual lanes, and compose a new vector by mixing lanes from two source vectors:

```csharp
// Create a vector from individual lane values
var v = Vector128.Create(1.0f, 2.0f, 3.0f, 4.0f);

// Extract a lane
float lane2 = Vector128.GetElement(v, 2); // 3.0f

// Compose: take lanes 0,1 from v1 and lanes 2,3 from v2
var v1 = Vector128.Create(10f, 20f, 30f, 40f);
var v2 = Vector128.Create(50f, 60f, 70f, 80f);
```

These APIs complement the existing `Vector128.Shuffle` and element-manipulation methods, providing a higher-level, hardware-independent interface for lane-level data manipulation without resorting to unsafe pointer casts.

## Stream wrappers for memory and text-based types

New `Stream` wrappers are available for adapting memory-backed and text-based types to the `Stream` interface ([dotnet/runtime #129811](https://github.com/dotnet/runtime/pull/129811)). The additions include:

- `Stream.AsStream()` extension on `ReadOnlyMemory<byte>` and `Memory<byte>` — creates a stream backed by the memory segment with no copy
- `Stream.AsStream()` extension on `ReadOnlySequence<byte>` — streams across a sequence of memory segments
- `TextWriter`-to-`Stream` adapter — wraps a `TextWriter` as a stream that encodes bytes on write

These wrappers fill common interop scenarios where an API requires a `Stream` but the data is already in memory or in a `TextWriter`. They avoid allocating intermediate buffers and work naturally with `async`/`await` through the existing memory-based stream paths.

## JIT optimizations

### `SELECT(cond, cns, cns)` folded to `cns`

The JIT now eliminates conditional-select nodes where both branches produce the same constant ([dotnet/runtime #127915](https://github.com/dotnet/runtime/pull/127915)). When the IR contains `SELECT(condition, k, k)`, the result is always `k` regardless of the condition, so the entire node collapses to the constant. This is a cleanup that removes redundant nodes generated by earlier IR lowering passes and reduces code size for conditional expressions.

### Loop inversion for oversize loops

The JIT can now invert loops that carry their own bounds checks — converting a `while` loop to a `do-while` plus an outer guard — when the loop body is too large for the standard loop inversion heuristic ([dotnet/runtime #129722](https://github.com/dotnet/runtime/pull/129722)). This enables better range-check elimination and reduces the number of bounds checks in loops that operate on arrays or spans.

### Canonicalized loop backedges

The JIT now rewrites loop control flow so each natural loop has exactly one backedge, which it targets at a single latch block ([dotnet/runtime #128303](https://github.com/dotnet/runtime/pull/128303)). This makes loops cheaper to analyze for subsequent optimization passes (induction-variable recognition, range-check hoisting) because they all have a uniform shape. The transformation is purely structural — it does not change loop semantics.

## Improved `Math.BigMul` performance on x64

`Math.BigMul(ulong, ulong, out ulong)` — which multiplies two 64-bit unsigned integers and returns the 128-bit product — is now significantly faster on x64 processors ([dotnet/runtime #117261](https://github.com/dotnet/runtime/pull/117261)). The implementation now emits the single `MUL r/m64` instruction that produces a 128-bit result in `RDX:RAX`, replacing the multi-instruction sequence that used 32-bit arithmetic. This matters for big-integer arithmetic, cryptographic code, and hashing algorithms that rely on wide multiplications.

## OpenBSD platform improvements

`System.Net.Http` is now supported on OpenBSD ([dotnet/runtime #129475](https://github.com/dotnet/runtime/pull/129475)), including `HttpClient`, `SocketsHttpHandler`, and TLS through the platform's native SSL library. `System.IO.FileSystem.Watcher` (`FileSystemWatcher`) is also now functional on OpenBSD using `kqueue` ([dotnet/runtime #129583](https://github.com/dotnet/runtime/pull/129583)). Together these bring .NET 11 networked and file-watching scenarios to OpenBSD without requiring workarounds.

## Security and correctness improvements

### `ZipArchiveEntry` validates uncompressed size before decompression

When opening a ZIP archive entry for update, `ZipArchiveEntry` now validates the declared uncompressed size against reasonable bounds before allocating the decompression buffer ([dotnet/runtime #128319](https://github.com/dotnet/runtime/pull/128319)). This closes a class of ZIP bomb payloads where a tiny compressed stream claimed an enormous uncompressed size, causing `MemoryStream` to pre-allocate gigabytes of backing memory.

### DNS hostname null-character validation

`System.Net.Dns` now rejects hostnames containing embedded null characters (`\0`) at the API boundary ([dotnet/runtime #128982](https://github.com/dotnet/runtime/pull/128982)). Embedded null characters can cause a hostname to be silently truncated by native string functions, potentially resolving a different host than intended. The validation throws `ArgumentException` before the name is passed to the resolver.

## In-process crash report logging

When a .NET process crashes, the runtime can now write a crash report to disk from within the faulting process before the process exits ([dotnet/runtime #128105](https://github.com/dotnet/runtime/pull/128105)). Previously, crash reporting required an external child process launched via `createdump`. The new in-process path captures exception information, the faulting thread's stack, and basic process metadata without needing the external process, making crash diagnostics available in environments where spawning child processes is restricted (containers, sandboxed environments).

## Breaking changes

- `AsnEncodedData.RawData` setter is now obsolete. Callers that set `RawData` directly should reconstruct the `AsnEncodedData` instance instead ([dotnet/runtime #129765](https://github.com/dotnet/runtime/pull/129765)).

## Bug fixes

- **Runtime-async** — Fix async stack-walk crash for continuations with a null diagnostic IP ([dotnet/runtime #128496](https://github.com/dotnet/runtime/pull/128496)).
- **DI** — `DefaultPartitionedRateLimiter` heartbeat now correctly disposes `NoopLimiter` ([dotnet/runtime #127582](https://github.com/dotnet/runtime/pull/127582)).
- **NativeAOT** — Corrects `ValueType.GetHashCode` for types with nested generic fields ([dotnet/runtime #129728](https://github.com/dotnet/runtime/pull/129728)).
- **Sockets** — Fix infinite spin-wait when a socket is closed after its handle was invalidated ([dotnet/runtime #128434](https://github.com/dotnet/runtime/pull/128434)).
- **GC** — Fix GC hole when a method return is hijacked for GC suspension ([dotnet/runtime #129714](https://github.com/dotnet/runtime/pull/129714)).
- **COM interop** — `MarshalAs.IidParameterIndex` for `out object` is now honored in source-generated COM stubs ([dotnet/runtime #128214](https://github.com/dotnet/runtime/pull/128214)).
- **QUIC** — Throws on write after the writing side of a QUIC stream is closed ([dotnet/runtime #128494](https://github.com/dotnet/runtime/pull/128494)).
- **X.509** — Fix `OpenSSL X509Chain` time-validity check when the process time zone differs from UTC ([dotnet/runtime #129394](https://github.com/dotnet/runtime/pull/129394)).

## Community contributors

Thank you contributors! ❤️

- [@hez2010](https://github.com/hez2010) — JIT constant folding for `SequenceEqual` (prior previews) and several follow-ups
- [@0xced](https://github.com/0xced) — OpenBSD networking fixes
- [@filipnavara](https://github.com/filipnavara) — OpenBSD platform work
