# Entity Framework Core in .NET 11 Preview 6 - Release Notes

.NET 11 Preview 6 includes new Entity Framework Core features & enhancements:

<!-- toc -->

- [FULL OUTER JOIN support](#full-outer-join-support)
- [SQL Server JSON column indexes](#sql-server-json-column-indexes)
- [Cosmos index improvements](#cosmos-index-improvements)
- [Wildcard migration operations](#wildcard-migration-operations)
- [Unconstrained foreign key relationships](#unconstrained-foreign-key-relationships)
- [LINQ translation improvements](#linq-translation-improvements)
- [SQLite improvements](#sqlite-improvements)
- [Change tracker improvements](#change-tracker-improvements)
- [Community contributors](#community-contributors)

<!-- tocstop -->

## FULL OUTER JOIN support

EF Core now translates LINQ queries to SQL FULL OUTER JOIN ([dotnet/efcore #38340](https://github.com/dotnet/efcore/pull/38340)). A full outer join returns all rows from both sides, matching where possible and including unmatched rows with null values.

```csharp
var results = from left in dbContext.Left
              join right in dbContext.Right
                  on left.Key equals right.Key into joined
              from j in joined.DefaultIfEmpty()
              select new { left, j };
```

EF Core detects the pattern and emits `FULL OUTER JOIN` on databases that support it (SQL Server, PostgreSQL, SQLite). Databases that lack native FULL OUTER JOIN support continue to use the union-based fallback.

## SQL Server JSON column indexes

SQL Server JSON columns now support JSON indexes via the new `HasJsonIndex()` fluent API ([dotnet/efcore #38302](https://github.com/dotnet/efcore/pull/38302)):

```csharp
modelBuilder.Entity<Customer>()
    .HasIndex(c => c.Address)
    .HasJsonIndex();
```

JSON indexes improve performance for queries that filter or sort on properties inside a JSON column. Only SQL Server 2022 and Azure SQL supports this feature.

## Cosmos index improvements

Azure Cosmos DB indexes now have full configuration support ([dotnet/efcore #38360](https://github.com/dotnet/efcore/pull/38360)):

- **JSON indexes** — index properties of embedded JSON documents
- **Composite indexes** — multi-path indexes for efficient ORDER BY and filtered queries
- **Include indexes** — specify which properties are covered by an index
- **Exclude indexes** — selectively exclude paths from indexing

```csharp
modelBuilder.Entity<Customer>().HasIndex(c => new { c.Name, c.Email })
    .ForCosmos()
    .IsComposite();
```

## Wildcard migration operations

`GetMigrations`, `ScriptMigration`, and `DropDatabase` now accept a wildcard `*` as the starting migration name ([dotnet/efcore #38327](https://github.com/dotnet/efcore/pull/38327)). `*` expands to the earliest available migration, letting you script or verify all migrations without knowing the first migration name:

```bash
dotnet ef migrations script * latest --output full-schema.sql
```

## Unconstrained foreign key relationships

EF Core now supports relationships that have no foreign key constraint in the database ([dotnet/efcore #38361](https://github.com/dotnet/efcore/pull/38361)). Unconstrained relationships are useful for soft-delete scenarios, cross-schema relationships, and databases where constraint enforcement is handled at the application layer.

```csharp
modelBuilder.Entity<Order>()
    .HasOne(o => o.Customer)
    .WithMany(c => c.Orders)
    .HasForeignKey(o => o.CustomerId)
    .IsRequired(false)
    .HasConstraintName(null); // no FK constraint emitted
```

## LINQ translation improvements

Several new LINQ-to-SQL translations reduce the need for raw SQL in common query patterns:

- **`List<T>.Exists` → `EXISTS`** — `list.Exists(x => ...)` now translates to a SQL subquery using `EXISTS` ([dotnet/efcore #38226](https://github.com/dotnet/efcore/pull/38226))
- **`NULLIF` support** — conditional null expressions translate to `NULLIF(expr1, expr2)` ([dotnet/efcore #35327](https://github.com/dotnet/efcore/pull/35327))
- **Null propagation for `IS NOT NULL`** — null-propagating access patterns produce fewer redundant `IS NOT NULL` checks ([dotnet/efcore #34127](https://github.com/dotnet/efcore/pull/34127))
- **Better Cosmos cast/convert** — type cast and convert expressions translate correctly to Cosmos query syntax ([dotnet/efcore #35000](https://github.com/dotnet/efcore/pull/35000))
- **Keys and indexes through complex-type properties** — `HasKey` and `HasIndex` can now traverse complex-type properties ([dotnet/efcore #38192](https://github.com/dotnet/efcore/pull/38192))

## SQLite improvements

- **`UInt128` in `SqliteValueBinder`** — `UInt128` columns now bind correctly in SQLite ([dotnet/efcore #37492](https://github.com/dotnet/efcore/pull/37492))
- **`string.Join`/`Concat` with ordering** — these expressions now translate to SQL `group_concat(x ORDER BY y)` on SQLite ([dotnet/efcore #38344](https://github.com/dotnet/efcore/pull/38344))
- **`TimeOnly.Hour/Minute/Second`** — these members now translate on SQLite ([dotnet/efcore #38341](https://github.com/dotnet/efcore/pull/38341))

## Change tracker improvements

**Detached entries held weakly** — the change tracker now stores detached entries using weak references ([dotnet/efcore #38387](https://github.com/dotnet/efcore/pull/38387)). Detached entities that go out of scope no longer prevent garbage collection. Applications that track many short-lived entities can see lower memory usage.

**Type mappings generic for NativeAOT** — EF Core's type mapping infrastructure is now generic to support value comparers under NativeAOT ([dotnet/efcore #38440](https://github.com/dotnet/efcore/pull/38440)).

<!-- Filtered features:
  - IUpdateAdapter.CreateEntry overload (#38367): Provider extensibility API; too narrow for general audience.
  - Move IOperationReporter, ISnapshotModelProcessor to EFCore.Relational (#38408): Internal API promotion; provider author only.
  - IManyToManyLoaderFactory injectable (#38411): Internal extensibility; no direct user impact.
  - SQL Server temporal period columns not-hidden option (#38225): Narrow SQL Server feature.
-->

## Community contributors

Thank you contributors! ❤️

- [@roji](https://github.com/dotnet/efcore/pulls?q=is%3Apr+is%3Amerged+author%3Aroji)
- [@lajones](https://github.com/dotnet/efcore/pulls?q=is%3Apr+is%3Amerged+author%3Alajones)
