# Zig 0.15.2 Status

## Overview

This project targets Zig 0.15.2 and is fully migrated to current Zig container patterns.

## Current State

- `build.zig.zon` requires Zig `0.15.2`.
- Core query builders use `std.ArrayListUnmanaged` and explicit allocator passing.
- SQLite integration works with `vrischmann/zig-sqlite` using alloc-aware row decoding APIs for pointer/slice fields.
- Schema API is now the compact DSL:
  - `schema(.{ ... })`
  - `table("name", .{ ... })`
  - `col(T)`

## API Direction (Post-Upgrade)

- Strict/comptime lane:
  - compile-time validation of query construction
  - inferred `ResultType`
  - typed params via `param(...)` and `params(...)`
- Runtime lane:
  - dynamic query building
  - raw SQL escape hatch via `whereRaw(...)`
  - database helpers (`executeWith`, `queryOne`, `queryAll`)
  - transaction helpers (`begin`, `beginWithMode`, `commit`, `rollback`)

## Notes

- Legacy manual field declarations (`Field(T){ .table, .column }`) are still technically compatible in some internals/examples, but the recommended public API is `schema/table/col`.
- Direct `zig test src/core/database.zig` may fail in isolation because sqlite module wiring is done through `build.zig`; use `zig build test` for full integration.

## Verification

Recommended validation commands:

```bash
zig test src/core/type_safe.zig
zig test src/core/type_safety_audit.zig
zig build test
```

All of the above are currently passing.
