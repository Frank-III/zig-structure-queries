# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Compact schema DSL: `schema(.{ ... })`, `table("...", .{ ... })`, `col(T)`.
- `columns(table)` helper for selecting all declared table fields.
- Strict/comptime typed placeholder support:
  - `param("name", T)`
  - `params(.{ ... })`
  - `flattenedValuesWith(...)` and `flattenedValuesAs(...)`.
- Nested logical expression support (`and_` / `or_`) for runtime and strict builders.
- Join nullability inference in strict `ResultType`:
  - LEFT JOIN optionalizes right-side selected fields.
  - RIGHT JOIN optionalizes left-side selected fields.
- SQLite dialect operator coverage:
  - `GLOB`, `MATCH`, `REGEXP`
  - table-level FTS helper: `tableMatch(table, query)`.
- Runtime raw SQL escape hatch in `QueryBuilder`:
  - `whereRaw(sql_fragment, values)`.
- Database runtime convenience helpers:
  - `executeWith`, `queryOne`, `queryAll`.
- Transaction abstraction with explicit modes:
  - `begin`, `beginWithMode(.deferred|.immediate|.exclusive)`
  - commit/rollback/auto-rollback on scope exit.
- Integration tests for SQLite runtime queries, seeded data, and transaction behavior.

### Changed
- Migrated docs/examples to prefer schema DSL over manual `Field(...){ .table, .column }` declarations.
- Updated README status/limitations/contributing guidance to reflect current implementation.
- Updated Zig upgrade notes for current API direction and validation workflow.

### Fixed
- Runtime SQL rendering for null operators (`IS NULL` / `IS NOT NULL`) no longer appends extraneous values.
- Leaks on SQL generation error paths cleaned up in runtime builder.
