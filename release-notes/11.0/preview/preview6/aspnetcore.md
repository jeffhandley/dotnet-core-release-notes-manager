# ASP.NET Core in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new ASP.NET Core features and improvements:

<!-- toc -->

- [Blazor WebAssembly Out-of-Process Renderer](#blazor-webassembly-out-of-process-renderer)
- [`SupplyParameterFromSession` for Blazor](#supplyparameterfromsession-for-blazor)
- [CSRF protection via Fetch Metadata headers](#csrf-protection-via-fetch-metadata-headers)
- [Async validation in `Microsoft.Extensions.Validation`](#async-validation-in-microsoftextensionsvalidation)
- [OpenAPI 3.2 is now the default](#openapi-32-is-now-the-default)
- [Union types in OpenAPI, Minimal APIs, MVC, SignalR, and Blazor](#union-types-in-openapi-minimal-apis-mvc-signalr-and-blazor)
- [SignalR improvements](#signalr-improvements)
- [Blazor `Virtualize` improvements](#blazor-virtualize-improvements)
- [Blazor media components package](#blazor-media-components-package)
- [`RenderFragment` serialization](#renderfragment-serialization)
- [Antiforgery validation deferred to form consumers](#antiforgery-validation-deferred-to-form-consumers)
- [`dotnet-user-jwts` supports file-based apps](#dotnet-user-jwts-supports-file-based-apps)
- [Implicit middleware ordering fix](#implicit-middleware-ordering-fix)
- [`WebApplicationFactory.ConfigureHostApplicationBuilder`](#webapplicationfactoryconfigurehostapplicationbuilder)
- [`[ShortCircuit]` attribute for routing](#shortcircuit-attribute-for-routing)
- [Minimal API `JsonException` bubbles through problem details](#minimal-api-jsonexception-bubbles-through-problem-details)
- [Breaking changes](#breaking-changes)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

ASP.NET Core updates in .NET 11:

- [What's new in ASP.NET Core in .NET 11](https://learn.microsoft.com/aspnet/core/release-notes/aspnetcore-11)

## Blazor WebAssembly Out-of-Process Renderer

> This is a preview feature for .NET 11.

Blazor WebAssembly now supports an out-of-process renderer that runs the Blazor rendering pipeline on a separate WebAssembly thread, leaving the browser's main UI thread free for input handling and animations ([dotnet/aspnetcore #66442](https://github.com/dotnet/aspnetcore/pull/66442)). The renderer communicates with the main thread through a structured message channel, batching DOM mutations and forwarding JavaScript interop calls.

This is the foundational piece for multi-threaded Blazor WASM apps. With the out-of-process renderer:

- Long-running renders no longer block user input or drop frames
- Multiple rendering threads can coexist in a single app context
- JavaScript interop still works — calls are marshaled across the thread boundary automatically

The feature is enabled via the new `BrowserOptions` configuration API. The existing single-threaded render path remains the default; opt in per-app.

## `SupplyParameterFromSession` for Blazor

> This is a preview feature for .NET 11.

A new `[SupplyParameterFromSession]` attribute lets Blazor components receive parameter values from the session state store without manually reading from `ISessionService` ([dotnet/aspnetcore #65184](https://github.com/dotnet/aspnetcore/pull/65184)). Values are read from the session on render and written back when the component sets the parameter — the framework handles serialization and session lifecycle.

```csharp
@page "/checkout"

<p>Cart items: @CartItems?.Count</p>

@code {
    [SupplyParameterFromSession]
    public List<CartItem>? CartItems { get; set; }
}
```

`SupplyParameterFromSession` complements `SupplyParameterFromQuery` and `SupplyParameterFromForm` as part of a broader session-storage integration that can span streaming SSR, Server, and WebAssembly render modes.

## CSRF protection via Fetch Metadata headers

ASP.NET Core now includes a built-in CSRF algorithm based on [Fetch Metadata](https://www.w3.org/TR/fetch-metadata/) request headers (`Sec-Fetch-Site`, `Sec-Fetch-Mode`, `Sec-Fetch-Dest`) ([dotnet/aspnetcore #66585](https://github.com/dotnet/aspnetcore/pull/66585)). Modern browsers send these headers automatically, allowing the server to distinguish same-origin requests from cross-site requests without relying on hidden form tokens.

The Fetch Metadata check runs alongside (or optionally instead of) the existing antiforgery token approach. It rejects requests where:

- `Sec-Fetch-Site` indicates the request originated from a different origin
- The method is state-mutating (`POST`, `PUT`, `DELETE`, etc.)
- No explicit exemption is configured

This is most useful for APIs consumed by JavaScript clients that can't easily include form tokens, and for progressive adoption on apps that haven't fully deployed antiforgery tokens.

## Async validation in `Microsoft.Extensions.Validation`

`Microsoft.Extensions.Validation` now supports async validation through the `IAsyncValidatable` interface ([dotnet/aspnetcore #66487](https://github.com/dotnet/aspnetcore/pull/66487)). Models that implement `IAsyncValidatable` can await database lookups, external service checks, or other I/O during validation:

```csharp
public class CreateOrderRequest : IAsyncValidatable
{
    public Guid ProductId { get; set; }
    public int Quantity { get; set; }

    public async ValueTask<IEnumerable<ValidationResult>> ValidateAsync(
        ValidationContext context, CancellationToken cancellationToken)
    {
        var inventory = context.GetRequiredService<IInventoryService>();
        int available = await inventory.GetAvailableAsync(ProductId, cancellationToken);
        if (Quantity > available)
            yield return new ValidationResult($"Only {available} units available.", [nameof(Quantity)]);
    }
}
```

The validation middleware calls `ValidateAsync` after synchronous `IValidatableObject` validation completes.

## OpenAPI 3.2 is now the default

The ASP.NET Core OpenAPI document generator now defaults to OpenAPI 3.2 ([dotnet/aspnetcore #67097](https://github.com/dotnet/aspnetcore/pull/67097)). OpenAPI 3.2 adds support for:

- The `query` operation type (HTTP QUERY method)
- Stricter `$schema` and vocabulary handling
- Union type schemas using discriminators

Existing documents continue to work. If you need to stay on 3.0 or 3.1, set `OpenApiOptions.OpenApiVersion` explicitly:

```csharp
builder.Services.AddOpenApi(options =>
    options.OpenApiVersion = OpenApiSpecVersion.OpenApi3_0);
```

## Union types in OpenAPI, Minimal APIs, MVC, SignalR, and Blazor

C# 14 union types are now supported across the ASP.NET Core stack:

- **OpenAPI/ApiExplorer** — union types generate correct `oneOf` schemas in OpenAPI documents ([dotnet/aspnetcore #67001](https://github.com/dotnet/aspnetcore/pull/67001))
- **Minimal APIs** — union types work as endpoint parameters and return types, including in Request Delegates and compiled generators ([dotnet/aspnetcore #66951](https://github.com/dotnet/aspnetcore/pull/66951))
- **MVC / Razor Pages** — action parameters and return types can be union types ([dotnet/aspnetcore #67005](https://github.com/dotnet/aspnetcore/pull/67005))
- **SignalR** — hub method parameters and return types can be union types ([dotnet/aspnetcore #67125](https://github.com/dotnet/aspnetcore/pull/67125))
- **Blazor** — component parameter types can be union types, including correct prerendering for a `null` active case ([dotnet/aspnetcore #67296](https://github.com/dotnet/aspnetcore/pull/67296))

## SignalR improvements

### Auth token refresh

SignalR now supports refreshing access tokens without dropping the connection ([dotnet/aspnetcore #67400](https://github.com/dotnet/aspnetcore/pull/67400)). Both the server and the .NET `HubConnection` client can be configured with a `TokenProvider` callback that is invoked when the current token is close to expiry. The connection renegotiates authentication in the background, so long-running hub connections survive token expiry without requiring a reconnect:

```csharp
var connection = new HubConnectionBuilder()
    .WithUrl("https://example.com/hub", options =>
    {
        options.AccessTokenProvider = async () =>
            await tokenService.GetOrRefreshAccessTokenAsync();
    })
    .Build();
```

### Client-side cancellation of hub invocations

Clients can now cancel an in-flight `InvokeAsync` call before the server sends a response ([dotnet/aspnetcore #64098](https://github.com/dotnet/aspnetcore/pull/64098)). Pass a `CancellationToken` to `InvokeAsync` or `SendAsync`, and the client sends a cancellation message to the server, which can observe it through the hub method's `CancellationToken` parameter:

```csharp
using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
string result = await connection.InvokeAsync<string>("SlowMethod", cts.Token);
```

## Blazor `Virtualize` improvements

### `InitialIndex` and `ScrollToIndexAsync`

The `Virtualize<TItem>` component now accepts an `InitialIndex` parameter to start the viewport at a specific item, and exposes a `ScrollToIndexAsync` method to programmatically scroll to any item at runtime ([dotnet/aspnetcore #66753](https://github.com/dotnet/aspnetcore/pull/66753)):

```razor
<Virtualize @ref="virtualizeRef"
            Items="@items"
            InitialIndex="50">
    <ItemContent>
        <!-- item template -->
    </ItemContent>
</Virtualize>

@code {
    Virtualize<MyItem>? virtualizeRef;

    async Task ScrollToTop() =>
        await virtualizeRef!.ScrollToIndexAsync(0);
}
```

### CSP-compliant rendering

The `Virtualize` component no longer emits inline style attributes, making it compatible with strict Content Security Policies that forbid `style-src 'unsafe-inline'` ([dotnet/aspnetcore #66680](https://github.com/dotnet/aspnetcore/pull/66680)). The spacer element dimensions are now applied through scoped CSS classes.

## Blazor media components package

Blazor media components — currently `MediaCapture` and related types — have been moved to a dedicated `Microsoft.AspNetCore.Components.Media` package ([dotnet/aspnetcore #67130](https://github.com/dotnet/aspnetcore/pull/67130)). This separates the media API surface from the core Blazor framework, allowing it to evolve independently and keeping the default framework download smaller for apps that don't use media capture.

## `RenderFragment` serialization

Blazor `RenderFragment` delegates can now be serialized as part of component state, enabling scenarios like persisted prerender output and enhanced navigation where a render fragment must survive a round-trip through server state ([dotnet/aspnetcore #66528](https://github.com/dotnet/aspnetcore/pull/66528)).

## Antiforgery validation deferred to form consumers

> **Breaking change.** This is a behavior change that may require app updates.

Antiforgery validation is now deferred until the form consumer (a Minimal API handler, an MVC action, a Razor Page) reads the form body via `IAntiforgeryValidationFeature`, rather than running immediately in middleware ([dotnet/aspnetcore #67082](https://github.com/dotnet/aspnetcore/pull/67082)). This makes antiforgery compatible with endpoints that need to read the request body before deciding whether antiforgery applies — for example, endpoints that handle both JSON and form submissions.

Apps that relied on early middleware rejection of invalid tokens should verify that the deferred model works for their routing setup. Endpoints that do not read form data are unaffected.

## `dotnet-user-jwts` supports file-based apps

The `dotnet user-jwts` CLI tool now accepts a `--file` flag pointing to a `.cs` file-based app, and can read secrets from the app's inline configuration ([dotnet/aspnetcore #66919](https://github.com/dotnet/aspnetcore/pull/66919)). Previously, `dotnet user-jwts` required a project file.

```bash
dotnet user-jwts create --file MyApp.cs --name "Test User"
```

## Implicit middleware ordering fix

Implicit middlewares added via `UseRouting()` and similar convenience methods now execute after `UseRouting()` itself ([dotnet/aspnetcore #67307](https://github.com/dotnet/aspnetcore/pull/67307)). Previously, some implicit middlewares could run before the route was resolved, meaning they could not access `RouteData`. The fix makes middleware ordering consistent and allows implicit middleware to safely inspect the current route.

## `WebApplicationFactory.ConfigureHostApplicationBuilder`

`WebApplicationFactory<TEntryPoint>` now exposes a virtual `ConfigureHostApplicationBuilder` method that integration-test subclasses can override to configure the `IHostApplicationBuilder` before the app's `Program.cs` startup code runs ([dotnet/aspnetcore #66527](https://github.com/dotnet/aspnetcore/pull/66527)). This allows early test-time configuration — such as swapping services or setting environment variables — that was previously difficult without hacks in `ConfigureWebHost`.

## `[ShortCircuit]` attribute for routing

A new `[ShortCircuit]` attribute can be applied to endpoint handlers or route groups to indicate that the endpoint should skip subsequent middleware and return immediately after execution ([dotnet/aspnetcore #67249](https://github.com/dotnet/aspnetcore/pull/67249)). This is useful for health-check endpoints, static-asset endpoints, or any handler where running the full middleware pipeline is wasteful.

## Minimal API `JsonException` bubbles through problem details

`JsonException` thrown during request deserialization in Minimal APIs now propagates through the problem details middleware and produces a `400 Bad Request` response with a structured `ProblemDetails` body ([dotnet/aspnetcore #66519](https://github.com/dotnet/aspnetcore/pull/66519)). Previously, `JsonException` was caught silently in some paths, producing an empty or unhelpful response.

## Breaking changes

- **Antiforgery** — Validation is now deferred to form consumers via `IAntiforgeryValidationFeature` rather than running eagerly in middleware ([dotnet/aspnetcore #67082](https://github.com/dotnet/aspnetcore/pull/67082)).

## Bug fixes

- **Identity email** — Default Identity email copy improved for recipients who did not initiate the action ([dotnet/aspnetcore #66747](https://github.com/dotnet/aspnetcore/pull/66747)).
- **OpenAPI** — Duplicate XML documentation IDs for generic properties and references no longer appear in generated documents ([dotnet/aspnetcore #64404](https://github.com/dotnet/aspnetcore/pull/64404)).
- **Blazor hot reload** — `ShouldRender` bypass is now scoped to the first render per component, preventing an unbounded re-render loop ([dotnet/aspnetcore #67372](https://github.com/dotnet/aspnetcore/pull/67372)).
- **Response caching** — Responses for authenticated users are no longer cached ([dotnet/aspnetcore #67110](https://github.com/dotnet/aspnetcore/pull/67110)).
- **Blazor WebView** — `JSDisconnectedException` from `IJSObjectReference.DisposeAsync` is now caught and discarded gracefully ([dotnet/aspnetcore #66259](https://github.com/dotnet/aspnetcore/pull/66259)).
- **Minimal API OpenAPI** — `JsonSerializerOptions` are now propagated correctly during OpenAPI document generation ([dotnet/aspnetcore #66847](https://github.com/dotnet/aspnetcore/pull/66847)).
- **Certificates** — Windows certificate manager correctly detects user cancellation of the trust dialog ([dotnet/aspnetcore #66604](https://github.com/dotnet/aspnetcore/pull/66604)).

## Community contributors

Thank you contributors! ❤️

- [@Kahbazi](https://github.com/Kahbazi)
- [@DanielCordell](https://github.com/DanielCordell)
- [@nrjohnstone](https://github.com/nrjohnstone)
