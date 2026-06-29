# ASP.NET Core in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new ASP.NET Core features & enhancements:

<!-- toc -->

- [`SupplyParameterFromSession` for Blazor](#supplyparameterfromsession-for-blazor)
- [`Virtualize<TItem>` adds `InitialIndex` and `ScrollToIndexAsync`](#virtualizetitem-adds-initialindex-and-scrolltoindexasync)
- [`RenderFragment` serialization](#renderfragment-serialization)
- [Union types supported across ASP.NET Core](#union-types-supported-across-aspnet-core)
- [OpenAPI defaults to 3.2](#openapi-defaults-to-32)
- [`JsonException` surfaces in minimal API problem details](#jsonexception-surfaces-in-minimal-api-problem-details)
- [Breaking changes](#breaking-changes)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## `SupplyParameterFromSession` for Blazor

A new `[SupplyParameterFromSession]` attribute lets Blazor components receive cascade parameters that are automatically persisted to and restored from the HTTP session ([dotnet/aspnetcore #65184](https://github.com/dotnet/aspnetcore/pull/65184)).

This gives Blazor United apps a simple, attribute-based way to store component state across server prerender and client-side reconnect cycles without manually calling `PersistentComponentState`.

```csharp
@inject ISessionStorage Session

<p>User theme: @Theme</p>

@code {
    [SupplyParameterFromSession]
    public string Theme { get; set; } = "light";
}
```

## `Virtualize<TItem>` adds `InitialIndex` and `ScrollToIndexAsync`

The `Virtualize<TItem>` component gains two new features for programmatic scroll control ([dotnet/aspnetcore #66753](https://github.com/dotnet/aspnetcore/pull/66753)):

- `InitialIndex` — renders the list starting at the given item index on first display, without a visible scroll jump
- `ScrollToIndexAsync(int index)` — scrolls the virtual list to a specific item at runtime

```razor
<Virtualize Items="@items" InitialIndex="50">
    <ItemTemplate Context="item">
        <div>@item.Name</div>
    </ItemTemplate>
</Virtualize>
```

```csharp
await virtualize.ScrollToIndexAsync(targetIndex);
```

## `RenderFragment` serialization

Blazor `RenderFragment` values can now be serialized and transmitted across the render tree boundary ([dotnet/aspnetcore #66528](https://github.com/dotnet/aspnetcore/pull/66528)). This underpins new Blazor United scenarios where a `RenderFragment` produced on the server can be cached, serialized, and rehydrated on the client without a round-trip.

## Union types supported across ASP.NET Core

C# 14 union types can now flow through the full ASP.NET Core stack:

- **Minimal APIs** — union types are supported as endpoint parameters and return types in both `RouteDataFilter` and `RouteDataGenerator` ([dotnet/aspnetcore #66951](https://github.com/dotnet/aspnetcore/pull/66951))
- **MVC / Razor Pages** — union types work as action parameters and return types ([dotnet/aspnetcore #67005](https://github.com/dotnet/aspnetcore/pull/67005))
- **SignalR** — union types are supported as hub method parameters and return types ([dotnet/aspnetcore #67125](https://github.com/dotnet/aspnetcore/pull/67125))
- **Blazor** — union types can be used as component parameters and cascade values; prerendering of unions with a null active case is fixed ([dotnet/aspnetcore #67296](https://github.com/dotnet/aspnetcore/pull/67296))
- **OpenAPI / ApiExplorer** — union types are described correctly in generated OpenAPI documents ([dotnet/aspnetcore #67001](https://github.com/dotnet/aspnetcore/pull/67001))

## OpenAPI defaults to 3.2

The default OpenAPI version emitted by `builder.Services.AddOpenApi()` is now OpenAPI 3.2 ([dotnet/aspnetcore #67097](https://github.com/dotnet/aspnetcore/pull/67097)). Microsoft.OpenApi is updated to 3.6.0 ([dotnet/aspnetcore #66998](https://github.com/dotnet/aspnetcore/pull/66998)). The OpenAPI 3.2 format adds the `discriminator` keyword support needed for union types, and brings fuller JSON Schema alignment.

## `JsonException` surfaces in minimal API problem details

`JsonException` thrown from a minimal API endpoint now propagates through `IProblemDetailsService` rather than being swallowed ([dotnet/aspnetcore #66519](https://github.com/dotnet/aspnetcore/pull/66519)). This lets custom problem details writers inspect and format JSON parse errors, giving callers structured error responses instead of generic 500s.

## Breaking changes

- **`NavigationManager.GetUriWithFragment`** — The Blazor `NavigationManager` API is renamed to `GetUriWithFragment` to better reflect what it does ([dotnet/aspnetcore #67368](https://github.com/dotnet/aspnetcore/pull/67368)).
- **`EnvironmentBoundary` renamed to `EnvironmentView`** — The Blazor `EnvironmentBoundary` component is renamed to `EnvironmentView` ([dotnet/aspnetcore #67369](https://github.com/dotnet/aspnetcore/pull/67369)). Update component references in markup accordingly.
- **OpenAPI default version is 3.2** — Applications that rely on 3.1 output from `AddOpenApi()` must now pin the version explicitly via `options.OpenApiVersion = OpenApiSpecVersion.OpenApi3_0`.

<!-- Filtered features:
  - HttpSys HttpQueryRequestProperty wrapper (#66700): Internal HttpSys plumbing; no end-user API.
  - Blazor media components separation (#67130): Internal SDK asset grouping, no behavioral change for developers.
  - ASP0027 suppressor for attributed partial Program (#66875): Narrow analyzer fix; bug-fix level.
  - Reject ASCII control chars in cookie auth return URLs (#66876): Security fix; routes to bug fixes.
-->

## Bug fixes

- **Blazor**
  - Fixed WebView `blazor.modules.json` publish crash ([dotnet/aspnetcore #67401](https://github.com/dotnet/aspnetcore/pull/67401))
  - Fixed Hot Reload scope of `ShouldRender` bypass to prevent OOM re-render loops ([dotnet/aspnetcore #67372](https://github.com/dotnet/aspnetcore/pull/67372))
  - ASP0027 analyzer is no longer emitted for attributed public partial Program declarations ([dotnet/aspnetcore #66875](https://github.com/dotnet/aspnetcore/pull/66875))
- **Security**
  - Cookie authentication now rejects redirect URLs containing ASCII control characters ([dotnet/aspnetcore #66876](https://github.com/dotnet/aspnetcore/pull/66876))
- **OpenAPI**
  - `JsonSerializerOptions` now propagates correctly during OpenAPI generation ([dotnet/aspnetcore #66847](https://github.com/dotnet/aspnetcore/pull/66847))
  - Fixed duplicate XML documentation IDs for generic properties ([dotnet/aspnetcore #64404](https://github.com/dotnet/aspnetcore/pull/64404))
  - Fixed handling of `DescriptionAttribute` for nullable value types ([dotnet/aspnetcore #65245](https://github.com/dotnet/aspnetcore/pull/65245))

## Community contributors

Thank you contributors! ❤️

- [@aidmsu](https://github.com/dotnet/aspnetcore/pulls?q=is%3Apr+is%3Amerged+author%3Aaidmsu)
