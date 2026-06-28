# Entity Framework Core in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new EF Core features and tooling improvements:

<!-- toc -->

- [`FULL OUTER JOIN` support](#full-outer-join-support)
- [SQL Server JSON indexes](#sql-server-json-indexes)
- [Keys and indexes through complex-type properties](#keys-and-indexes-through-complex-type-properties)
- [EF1003: detect `string.Format`/`string.Concat` in raw SQL APIs](#ef1003-detect-stringformatstringconcat-in-raw-sql-apis)
- [Wildcard `*` in migration CLI commands](#wildcard--in-migration-cli-commands)
- [`List<T>.Exists()` translated to SQL](#listtexists-translated-to-sql)
- [Cosmos DB: `Any()` translates to `LIMIT 1`](#cosmos-db-any-translates-to-limit-1)
- [`string.Join`/`string.Concat` with ordering on SQLite](#stringjoinstringconcat-with-ordering-on-sqlite)
- [`UInt128` support in SQLite value binder](#uint128-support-in-sqlite-value-binder)
- [Bug fixes](#bug-fixes)
- [Community contributors](#community-contributors)

<!-- tocstop -->

EF Core updates in .NET 11:

- [What's new in EF Core](https://learn.microsoft.com/ef/core/what-is-new/ef-core-11.0/whatsnew)

## `FULL OUTER JOIN` support

EF Core now translates LINQ queries that require a full outer join ([dotnet/efcore #38340](https://github.com/dotnet/efcore/pull/38340)). A full outer join returns all rows from both sides, with `null` values for unmatched columns. The translation is used automatically when EF Core detects that neither a left nor a right join is sufficient:

```csharp
var results = from left in db.Left
              join right in db.Right
              on left.Key equals right.Key into rightGroup
              from r in rightGroup.DefaultIfEmpty()
              select new { left.Name, RightName = r != null ? r.Name : null };
```

EF Core emits `FULL OUTER JOIN` for SQL Server, PostgreSQL, and other providers that support it. For providers that don't support the syntax natively, EF Core falls back to a union of a left join and an anti-join.

## SQL Server JSON indexes

SQL Server JSON indexes can now be configured through EF Core's fluent API ([dotnet/efcore #38302](https://github.com/dotnet/efcore/pull/38302)). SQL Server 2022 (and Azure SQL) support computed column indexes on `JSON_VALUE` expressions; EF Core now generates the correct `CREATE INDEX ... ON ... (JSON_VALUE(...))` DDL in migrations:

```csharp
modelBuilder.Entity<Product>()
    .HasIndex(p => p.MetadataJson)
    .HasAnnotation("SqlServer:JsonIndexPath", "$.category");
```

This is particularly useful for tables that store JSON blobs and need to query on specific JSON properties at scale.

## Keys and indexes through complex-type properties

Keys and indexes can now be configured on properties that traverse through complex-type (owned) navigations ([dotnet/efcore #38192](https://github.com/dotnet/efcore/pull/38192)). Previously, `HasKey` and `HasIndex` required the properties to be directly on the entity root; they now accept dotted paths like `"Address.PostalCode"`:

```csharp
modelBuilder.Entity<Customer>()
    .HasIndex(c => c.Address.PostalCode)  // traverses into the Address complex type
    .HasDatabaseName("IX_Customer_PostalCode");
```

This enables composite indexes and unique constraints on complex-type properties without needing to flatten them onto the entity.

## EF1003: detect `string.Format`/`string.Concat` in raw SQL APIs

A new analyzer, EF1003, detects calls to raw SQL APIs (`FromSqlRaw`, `ExecuteSqlRaw`, `SqlQuery`) where the SQL string is constructed with `string.Format` or `string.Concat` ([dotnet/efcore #38208](https://github.com/dotnet/efcore/pull/38208)). These patterns can introduce SQL injection vulnerabilities because the string is treated as a literal SQL fragment rather than a parameterized query. The analyzer suggests switching to the interpolated equivalents (`FromSql`, `ExecuteSql`) which automatically parameterize values.

```csharp
// EF1003: string.Format in raw SQL API
var blogs = db.Blogs.FromSqlRaw(string.Format("SELECT * FROM Blogs WHERE Name = '{0}'", name));

// Correct: use interpolated overload — EF Core parameterizes the value
var blogs = db.Blogs.FromSql($"SELECT * FROM Blogs WHERE Name = '{name}'");
```

## Wildcard `*` in migration CLI commands

`dotnet ef migrations list`, `dotnet ef migrations script`, and `dotnet ef database drop` now accept a wildcard `*` as a migration target ([dotnet/efcore #38327](https://github.com/dotnet/efcore/pull/38327)). Specifying `*` means "all migrations" or "use the latest migration" depending on the command, without having to know the exact migration name. This is useful in CI scripts that apply all pending migrations without embedding the latest migration name in the script.

## `List<T>.Exists()` translated to SQL

LINQ `List<T>.Exists(predicate)` calls inside EF Core queries are now translated to SQL `EXISTS` (or equivalent) rather than evaluated client-side ([dotnet/efcore #38226](https://github.com/dotnet/efcore/pull/38226)). This translation is consistent with the existing `Enumerable.Any` translation:

```csharp
var tags = new List<string> { "dotnet", "csharp" };
var blogs = db.Blogs.Where(b => tags.Exists(t => b.Tags.Contains(t))).ToList();
// Previously: loaded all blogs, then filtered in memory
// Now: translated to SQL EXISTS subquery
```

## Cosmos DB: `Any()` translates to `LIMIT 1`

`IQueryable.Any()` on a Cosmos DB collection now generates `SELECT VALUE 1 FROM c LIMIT 1` instead of a full `EXISTS` subquery ([dotnet/efcore #38297](https://github.com/dotnet/efcore/pull/38297)). Cosmos DB's execution engine processes `LIMIT 1` more cheaply than `EXISTS`, resulting in lower RU consumption and faster response times for existence checks on large collections.

## `string.Join`/`string.Concat` with ordering on SQLite

SQLite queries that call `string.Join` or `string.Concat` with an `OrderBy` clause inside the aggregate are now translated to SQL ([dotnet/efcore #38344](https://github.com/dotnet/efcore/pull/38344)), using SQLite's `group_concat` with `ORDER BY`. Previously these expressions caused an exception or fell back to client evaluation.

## `UInt128` support in SQLite value binder

SQLite's value binder now handles `System.UInt128` values ([dotnet/efcore #37492](https://github.com/dotnet/efcore/pull/37492)), storing them as `BLOB` or `TEXT` based on the configured column type. This completes the unsigned integer coverage for SQLite alongside the existing `uint`, `ulong`, and `UInt64` support.

## Bug fixes

- **GroupBy** — Fixed `InvalidOperationException` when a `GroupBy(...).Select(...)` projection uses an empty projection member ([dotnet/efcore #38140](https://github.com/dotnet/efcore/pull/38140)).
- **SelectMany** — Fixed `NullReferenceException` for `SelectMany` with inline array values ([dotnet/efcore #38286](https://github.com/dotnet/efcore/pull/38286)).
- **JSON filtering** — Fixed `InvalidOperationException` when filtering on a JSON column of an entity mapped to a database view ([dotnet/efcore #38321](https://github.com/dotnet/efcore/pull/38321)).
- **SQL Server `SIGN()`** — `Math.Sign` is now wrapped in `CAST(... AS int)` to prevent implicit numeric widening in SQL Server expressions ([dotnet/efcore #38260](https://github.com/dotnet/efcore/pull/38260)).
- **NativeAOT publish** — Fixed a case where EF Core's NativeAOT publish did not rebuild the RID-specific assembly after source generation ([dotnet/efcore #38322](https://github.com/dotnet/efcore/pull/38322)).

## Community contributors

Thank you contributors! ❤️

- [@ChrisJollyAU](https://github.com/ChrisJollyAU) — `string.Join`/`string.Concat` ordering on SQLite
- [@wertzui](https://github.com/wertzui) — wildcard `*` migration support
- [@jspuij](https://github.com/jspuij)
