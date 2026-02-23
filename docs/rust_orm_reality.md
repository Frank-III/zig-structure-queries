# Rust ORMs and Type Safety: Reality Check

## The Claim vs. Reality

Many Rust ORMs claim "type-safe queries" but what do they actually deliver?

## Diesel - The Most Mature Rust ORM

### What Diesel Actually Does

```rust
// Schema definition (generated from database)
table! {
    users (id) {
        id -> Int4,
        name -> Text,
        email -> Text,
    }
}

// Query
let results = users
    .filter(name.eq("John"))
    .select((id, name))
    .load::<(i32, String)>(&conn)?;
    //     ^^^^^^^^^^^^^ You MUST specify the type!
```

**Critical Point**: You must manually specify the result type `(i32, String)`. Diesel doesn't infer it!

### Why Diesel Can't Infer Result Types

```rust
// This is what we'd want:
let results = users
    .select((id, name))
    .load(&conn)?;  // Should be (i32, String) automatically

// But Rust's type system can't do this because:
// 1. select() returns a generic SelectStatement<...>
// 2. The type parameters become incredibly complex
// 3. You'd need Higher-Kinded Types (HKTs) which Rust doesn't have
```

### What Diesel's Macros Actually Do

```rust
// The table! macro generates:
pub struct users;
pub struct id;
pub struct name;

impl Table for users { ... }
impl Column for id { type SqlType = Int4; }
impl Column for name { type SqlType = Text; }
```

It's just code generation for boilerplate - NOT dynamic type inference!

## SQLx - The "Compile-Time Checked" SQL

### The Marketing vs. Reality

```rust
// SQLx claims this is "compile-time checked"
let user: (i32, String) = sqlx::query_as!(
    "(i32, String)",  // You STILL specify the type!
    "SELECT id, name FROM users WHERE id = ?",
    user_id
)
.fetch_one(&pool)
.await?;
```

### What SQLx Actually Does

1. **At compile time**: Connects to your database
2. **Validates**: The SQL query is valid
3. **Checks**: The types match what you specified
4. **Does NOT**: Infer the result type from the query

It's validation, not inference!

## SeaORM - The "Async Dynamic" ORM

```rust
// SeaORM query
let users: Vec<user::Model> = User::find()
    .filter(user::Column::Name.contains("John"))
    .all(&db)
    .await?;

// But for custom selections:
let results: Vec<(String, i32)> = User::find()
    .select_only()
    .column(user::Column::Name)
    .column(user::Column::Age)
    .into_tuple::<(String, i32)>()  // Manual type specification!
    .all(&db)
    .await?;
```

Again, you specify the result type manually!

## Toasty - What It Actually Does

Looking at your example:

```rust
#[toasty::model]
struct User {
    id: Id<Self>,
    name: String,
    todos: [Todo],
}

// This generates methods like:
impl User {
    async fn get_by_id(db: &Db, id: &Id<User>) -> Result<User> { ... }
    //                                             ^^^^^^^^^^^^
    //                                             Fixed return type!
}
```

Toasty generates CRUD methods with **fixed, known types**. It's not a dynamic query builder!

## The Fundamental Problem in Rust

### What We Want (But Can't Have)

```rust
// Hypothetical API
let query = users::table
    .select(users::name)     // Select name (String)
    .select(users::age);     // Select age (i32)

// This should automatically be Vec<(String, i32)>
let results = query.load(&conn)?;
```

### Why Rust Can't Do This

1. **No Higher-Kinded Types (HKTs)**
   ```rust
   // We'd need something like:
   trait SelectBuilder<Fields> {
       type Output = TupleOf<Fields>;  // Can't express this!
   }
   ```

2. **Type Parameters Explode**
   ```rust
   // Diesel's actual SelectStatement type:
   SelectStatement<
       From,
       Select,
       Distinct,
       Where,
       Order,
       LimitOffset,
       GroupBy,
       Having,
       Locking
   >
   // Each operation creates a new type with different parameters!
   ```

3. **Const Generics Are Limited**
   ```rust
   // We can't do:
   struct Query<const FIELDS: [Type]>;  // Not possible!
   ```

## What About TypeScript ORMs?

TypeScript actually gets closer because of its type system:

```typescript
// Prisma can actually infer this!
const users = await prisma.user.findMany({
    select: {
        name: true,
        age: true
    }
});
// users is automatically: { name: string, age: number }[]
```

Why? TypeScript has:
- Mapped types
- Template literal types
- Conditional types
- Type-level programming

## What About Swift?

Swift gets even closer with result builders:

```swift
let query = From(User.table)
    .select(\.name)
    .select(\.age)
    .where(\.age > 25)

// Swift can infer: [(name: String, age: Int)]
let results = try query.execute(db)
```

Swift has:
- Powerful generics with associated types
- Result builders (formerly function builders)
- KeyPaths with type information

## The Honest Truth

### What Rust ORMs Actually Provide

1. **SQL Validation** - Check your SQL is valid (SQLx)
2. **Schema Generation** - Generate structs from database (Diesel)
3. **Query Building** - Type-safe query construction (all of them)
4. **CRUD Operations** - Generated methods with known types (Toasty, SeaORM)

### What They DON'T Provide

1. **Automatic result type inference from dynamic queries**
2. **Truly generic query builders with inferred results**
3. **The ability to select arbitrary fields and get the right type**

### The Pattern They All Use

```rust
// You ALWAYS end up doing one of:

// Option 1: Fixed struct types
let users: Vec<User> = query.load(&conn)?;

// Option 2: Manual tuple types
let results: Vec<(String, i32)> = query.load(&conn)?;

// Option 3: Type annotation in macro
sqlx::query_as!(MyType, "SELECT ...")

// Option 4: Into a specific type
query.into_tuple::<(String, i32)>()
```

## Why Zig Actually Has Similar Limitations

Both Rust and Zig lack:
1. **Runtime type generation** that becomes compile-time types
2. **Higher-kinded types** for complex generic programming
3. **Dependent types** that could track query state

The difference is:
- Rust has macros that can generate lots of boilerplate
- Zig has comptime that can do some type generation
- Neither can do true dynamic-to-static type inference

## Conclusion

**No current Rust ORM achieves true type-safe query building with automatic result type inference.** They all require you to:

1. Use predefined model structs (limiting flexibility)
2. Manually specify result types for custom queries
3. Use macros that validate but don't infer

The marketing often overstates what "type safety" means. They provide:
- ✅ Compile-time SQL validation
- ✅ Type-safe query construction
- ❌ Automatic result type inference from arbitrary queries

This is a fundamental limitation of Rust's type system, not a failing of the ORMs.