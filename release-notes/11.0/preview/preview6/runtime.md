# .NET Runtime in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new Runtime features & enhancements:

<!-- toc -->

- [ARM64 pointer authentication for return addresses](#arm64-pointer-authentication-for-return-addresses)
- [New SIMD lane construction and composition APIs](#new-simd-lane-construction-and-composition-apis)
- [`Process.Run` and `Process.RunAsync` support a `silent` parameter](#processrun-and-processrunasync-support-a-silent-parameter)
- [`Process.StartSuspended` and `SafeProcessHandle.Resume` on Windows](#processstartsuspended-and-safeprocesshandleresume-on-windows)
- [COM source generator supports properties](#com-source-generator-supports-properties)
- [GC improvements for dependent handles](#gc-improvements-for-dependent-handles)
- [`Vector<T>` passed by reference when hardware vector size is available](#vectort-passed-by-reference-when-hardware-vector-size-is-available)
- [CoreCLR interpreter uses computed goto dispatch](#coreclr-interpreter-uses-computed-goto-dispatch)
- [New SVE2 intrinsics](#new-sve2-intrinsics)
- [JIT improvements](#jit-improvements)
- [OpenBSD porting progress](#openbsd-porting-progress)
- [Breaking changes](#breaking-changes)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## ARM64 pointer authentication for return addresses

The JIT now generates ARM64 PAC-RET instructions on processors that support pointer authentication ([dotnet/runtime #127838](https://github.com/dotnet/runtime/pull/127838)). Pointer authentication signs return addresses before pushing them onto the stack and authenticates them on return. This makes it harder for an attacker to corrupt the control flow of a managed application on ARMv8.3+ hardware by overwriting saved return addresses.

PAC-RET is enabled automatically when running on a PAC-capable processor; no application changes are required.

## New SIMD lane construction and composition APIs

New APIs for constructing SIMD vectors from individual lane values and composing vectors from sub-vectors are now available ([dotnet/runtime #129627](https://github.com/dotnet/runtime/pull/129627)). These allow writing more expressive hardware-accelerated code without resorting to unsafe pointer manipulation.

```csharp
// Construct a Vector128<int> from a scalar in a specific lane
var v = Vector128.Create(0, 1, 2, 3);
var lane0 = v.GetElement(0);
```

## `Process.Run` and `Process.RunAsync` support a `silent` parameter

Both `Process.Run` and `Process.RunAsync` now accept a `bool silent` parameter ([dotnet/runtime #129509](https://github.com/dotnet/runtime/pull/129509)). When `silent: true`, stdout and stderr from the child process are redirected and suppressed. This makes it easier to run helper processes without cluttering the console output.

```csharp
var result = await Process.RunAsync("git", "status", silent: true);
Console.WriteLine(result.ExitCode);
```

## `Process.StartSuspended` and `SafeProcessHandle.Resume` on Windows

`Process.StartSuspended` on Windows starts a new process in a suspended state, and `Resume` on the returned `SafeProcessHandle` then resumes it ([dotnet/runtime #129512](https://github.com/dotnet/runtime/pull/129512)). This lets you inject environment, change handles, or attach a debugger before the process runs any code.

```csharp
using SafeProcessHandle handle = Process.StartSuspended(startInfo);
// ... configure the suspended process
handle.Resume();
```

## COM source generator supports properties

The COM source generator now generates COM interop stubs for interface properties ([dotnet/runtime #128869](https://github.com/dotnet/runtime/pull/128869)). Previously only methods were supported, requiring hand-written marshalling code for property accessors in COM interfaces.

```csharp
[GeneratedComInterface]
partial interface IMyComInterface
{
    int Value { get; set; }  // get/set stubs are now generated automatically
}
```

## GC improvements for dependent handles

The garbage collector now ages dependent handles similarly to other objects ([dotnet/runtime #78746](https://github.com/dotnet/runtime/pull/78746)). Dependent handles that have survived several collections are promoted to older generations, reducing the frequency at which the GC has to scan them during minor collections. Applications with many dependent handles (such as conditional weak tables) may see lower GC pause times.

## `Vector<T>` passed by reference when hardware vector size is available

On platforms where `InstructionSet_VectorT` is available, `Vector<T>` arguments are now passed by reference rather than by value ([dotnet/runtime #125729](https://github.com/dotnet/runtime/pull/125729)). This reduces register pressure in methods that use platform-width vectors, which can produce smaller and faster code on AVX-512 and SVE2 capable hardware.

## CoreCLR interpreter uses computed goto dispatch

The CoreCLR interpreter now uses a computed goto (direct-threaded) dispatch loop instead of a switch statement ([dotnet/runtime #129216](https://github.com/dotnet/runtime/pull/129216)). Computed goto dispatch reduces branch mispredictions at the interpreter dispatch point and measurably improves interpreter throughput for workloads that rely on the interpreter.

## New SVE2 intrinsics

New SVE2 intrinsics are available for ARM Scalable Vector Extension workloads ([dotnet/runtime #128233](https://github.com/dotnet/runtime/pull/128233)):

- `CreateWhileWriteAfterRead*` — creates predicate vectors for write-after-read hazard detection
- `SaturatingExtract*` — extracts and saturates vector lane values

## JIT improvements

Several JIT optimizations landed in Preview 6 that benefit managed code without requiring source changes.

The JIT now inverts oversize loops that have their own bounds checks, moving the check outside the loop and reducing per-iteration overhead ([dotnet/runtime #129722](https://github.com/dotnet/runtime/pull/129722)). SSA-based `TryGetRange` now folds redundant comparisons into simpler forms ([dotnet/runtime #129354](https://github.com/dotnet/runtime/pull/129354)). The JIT also switches to an explicit range check when it is cheaper than the implicit bounds check ([dotnet/runtime #128524](https://github.com/dotnet/runtime/pull/128524)).

The single-IG prolog restriction has been removed, giving the JIT more freedom to place prolog code in the optimal emission group ([dotnet/runtime #126552](https://github.com/dotnet/runtime/pull/126552)).

## OpenBSD porting progress

Three major networking and file-watching stacks are now functional on OpenBSD:

- `System.Net.Security` ([dotnet/runtime #129479](https://github.com/dotnet/runtime/pull/129479))
- `System.Net.Http` ([dotnet/runtime #129475](https://github.com/dotnet/runtime/pull/129475))
- `System.IO.FileSystem.Watcher` ([dotnet/runtime #129583](https://github.com/dotnet/runtime/pull/129583))

## Breaking changes

- **`AsnEncodedData.RawData` setter obsoleted** — The `set` accessor on `AsnEncodedData.RawData` is marked `[Obsolete]` in .NET 11 ([dotnet/runtime #129765](https://github.com/dotnet/runtime/pull/129765)). Callers should construct a new `AsnEncodedData` instance instead of mutating the property. The setter will be removed in a future release.
- **TAR reader rejects negative PAX size values** — The TAR reader now rejects PAX archive entries with a negative uncompressed size value ([dotnet/runtime #128368](https://github.com/dotnet/runtime/pull/128368)). Well-formed archives are not affected.
- **ZIP update mode validates uncompressed size up front** — `ZipArchiveEntry` update mode now validates the declared uncompressed size before writing, rejecting archives where the value is inconsistent with the compressed data ([dotnet/runtime #128319](https://github.com/dotnet/runtime/pull/128319)).
- **DNS hostname validation rejects embedded null characters** — `Dns` now rejects hostnames that contain embedded null characters, which were previously passed through to the native resolver ([dotnet/runtime #128982](https://github.com/dotnet/runtime/pull/128982)).
- **DI keyed services: built-in services now probed correctly** — An edge case where keyed service probing skipped built-in DI services has been fixed ([dotnet/runtime #128198](https://github.com/dotnet/runtime/pull/128198)). Applications that depended on the broken lookup behavior may observe different resolution results.

<!-- Filtered features (significant engineering work, but too niche for release notes):
  - cDAC DacDbi API implementations: Multiple PRs implementing DacDbi APIs in cDAC. Internal runtime debugger plumbing; no direct developer impact.
  - Wasm RyuJIT codegen improvements: Contained bitcast, callfinally codegen. Wasm-specific runtime internals; very narrow audience.
  - [mono][llvm] Math intrinsics: Recognizes MathF.Abs/Log as intrinsics. Mono LLVM backend only; too narrow.
  - R2R generic virtual method discovery: Internal AOT plumbing. No public API surface.
  - [android] softfp ABI: Enables android-arm CoreCLR with softfp ABI. Android-specific platform porting; too narrow.
-->

## Bug fixes

- **System.Net.Sockets**
  - `Socket.Blocking` is now correctly set from the handle when constructing from `SafeSocketHandle` ([dotnet/runtime #128433](https://github.com/dotnet/runtime/pull/128433))
  - Fixed infinite release spin-wait when `Socket` is closed after the handle was invalidated ([dotnet/runtime #128434](https://github.com/dotnet/runtime/pull/128434))
- **System.Net.Security**
  - Improved accuracy of `SslClientHelloInfo` ([dotnet/runtime #128244](https://github.com/dotnet/runtime/pull/128244))
- **COM interop**
  - `MarshalAs.IidParameterIndex` is now honored for `out object` in source-generated COM stubs ([dotnet/runtime #128214](https://github.com/dotnet/runtime/pull/128214))
  - Fixed `MarshalAs` IID parameter index parsing ([dotnet/runtime #128364](https://github.com/dotnet/runtime/pull/128364))
- **Dependency Injection**
  - Shared singleton instances are no longer disposed twice during container teardown ([dotnet/runtime #128768](https://github.com/dotnet/runtime/pull/128768))
- **Diagnostics**
  - Fixed W3C Trace Context Level 2 compliance in the W3C propagator ([dotnet/runtime #129414](https://github.com/dotnet/runtime/pull/129414))
  - Fixed `NativeAOT` GC hole in `ReferenceTrackerNativeObjectWrapper` ([dotnet/runtime #129598](https://github.com/dotnet/runtime/pull/129598))
- **JIT**
  - Fixed JIT IV opt that incorrectly modified a counter live into an EH handler ([dotnet/runtime #129058](https://github.com/dotnet/runtime/pull/129058))
  - Fixed x64 `ToScalar` XMM→GPR codegen for contained `CreateScalar` operand ([dotnet/runtime #129644](https://github.com/dotnet/runtime/pull/129644))
  - Fixed ARM64 conditional select lowering ([dotnet/runtime #128700](https://github.com/dotnet/runtime/pull/128700))

## Community contributors

Thank you contributors! ❤️

- [@EgorBo](https://github.com/dotnet/runtime/pulls?q=is%3Apr+is%3Amerged+author%3AEgorBo)
