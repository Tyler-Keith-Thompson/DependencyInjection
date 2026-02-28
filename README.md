# DependencyInjection

A Swift 6 dependency injection framework with first-class async/await support, macro-based property injection, and test isolation that actually works with concurrent tests.

## Features

- **Swift 6 strict concurrency** -- fully `Sendable`, no data races
- **Four factory variants** -- sync, sync-throwing, async, async-throwing
- **Three scoping strategies** -- unique, cached, shared (weak)
- **Macro-based injection** -- `@Injected`, `@LazyInjected`, `@ConstructorInjected`
- **Hierarchical containers** -- nested scopes with parent fallback
- **Test container isolation** -- concurrent tests never interfere with each other
- **Leaked resolution detection** -- catches async work that escapes test scope
- **Composable test defaults** -- reusable test fixtures via result builders

## Requirements

- Swift 6.0+
- iOS 17+ / macOS 13+ / watchOS 10+ / tvOS 17+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/DependencyInjection.git", from: "1.0.0"),
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "DependencyInjection", package: "DependencyInjection"),
    ]
)
```

---

## Quick Start

### 1. Define your factories

```swift
import DependencyInjection

protocol Logger: Sendable {
    func log(_ message: String)
}

final class ConsoleLogger: Logger, Sendable {
    func log(_ message: String) { print(message) }
}

extension Container {
    static let logger = Factory { ConsoleLogger() as Logger }
}
```

### 2. Inject into your types

```swift
class OrderService {
    @Injected(Container.logger) var logger: Logger

    func placeOrder() {
        logger.log("Order placed")
    }
}
```

### 3. Swap in test doubles

```swift
@Test func orderServiceLogsOnPlacement() {
    withTestContainer {
        let spy = SpyLogger()
        Container.logger.register { spy as Logger }

        let service = OrderService()
        service.placeOrder()

        #expect(spy.messages == ["Order placed"])
    }
}
```

That's it. No protocols for the container, no complex registration ceremonies, no ambient singletons leaking across tests.

---

## Core Concepts

### Factories

A **Factory** is the unit of registration. It wraps a closure that knows how to create a dependency and automatically registers itself with `Container.default` on creation.

```swift
// Sync
static let logger = Factory { ConsoleLogger() as Logger }

// Sync throwing
static let config = Factory { try loadConfig() }

// Async
static let session = Factory { await URLSession.shared }

// Async throwing
static let database = Factory { try await Database.connect() }
```

The return type of the closure determines which factory type is created:

| Closure signature | Factory type |
|---|---|
| `() -> T` | `SyncFactory<T>` |
| `() throws -> T` | `SyncThrowingFactory<T>` |
| `() async -> T` | `AsyncFactory<T>` |
| `() async throws -> T` | `AsyncThrowingFactory<T>` |

Factories are callable. You can resolve a dependency by calling the factory directly:

```swift
let logger = Container.logger()              // sync
let config = try Container.config()          // sync throwing
let session = await Container.session()      // async
let db = try await Container.database()      // async throwing
```

### Container

`Container` is the resolution context. There is always a default global container (`Container.default`), and the framework uses Swift's `ServiceContext` to propagate the *current* container through async call chains.

```swift
// The container in the current async context
Container.current

// The global default (used when no context is set)
Container.default
```

Containers form a parent-child hierarchy. When resolving, a container checks its own storage first, then walks up to its parent.

### Scopes

Scopes control instance lifetime. Pass a scope when creating a factory:

```swift
static let logger   = Factory(scope: .unique)  { ConsoleLogger() }  // default
static let analytics = Factory(scope: .cached)  { AnalyticsService() }
static let session   = Factory(scope: .shared)  { Session() }
```

| Scope | Behavior | Use when |
|---|---|---|
| `.unique` | New instance every resolution | Stateless services, value types, or when you want a fresh instance each time |
| `.cached` | Created once, held with a strong reference forever | True singletons that live for the app's lifetime |
| `.shared` | Created once, held with a weak reference; recreated if all external references are released | Shared resources you want to deallocate when no longer in use |

Caches are **per-container** -- a test container gets its own cache, so cached singletons in tests never collide with production or other tests.

For async factories with `.cached` or `.shared` scope, concurrent resolutions are **deduplicated** -- only one async task runs the resolver, and all concurrent callers await the same result.

---

## Injection Macros

Three macros provide property-level injection. Each handles all four factory variants (sync, throwing, async, async-throwing) automatically.

### `@Injected` -- resolve on every access

```swift
class FeatureViewModel {
    @Injected(Container.logger) var logger: Logger
}
```

Every time you read `logger`, the factory resolves again. This is useful when the factory has `.unique` scope and you want the latest registration, or when combined with `.cached`/`.shared` scope where re-resolution is cheap (cache hit).

For throwing factories, the wrapped value is `Result<T, any Error>`:

```swift
@Injected(Container.config) var config: Result<Config, any Error>

func loadConfig() throws -> Config {
    try config.get()
}
```

For async factories, the wrapped value is a `Task`:

```swift
@Injected(Container.session) var session: Task<URLSession, Never>

func fetch() async {
    let s = await session.value
    // use s
}
```

### `@ConstructorInjected` -- resolve once at init

```swift
class PaymentProcessor {
    @ConstructorInjected(Container.gateway) var gateway: PaymentGateway
}
```

The dependency is resolved immediately when the owning type is initialized. The resolved value is stored and reused for the lifetime of the object. Async tasks are cancelled in `deinit`.

### `@LazyInjected` -- resolve on first access, then cache

```swift
class ReportGenerator {
    @LazyInjected(Container.formatter) var formatter: DateFormatter
}
```

The dependency is **not** resolved until the first time you read the property. After that, the resolved value is cached in the instance (thread-safe). Async tasks are started eagerly but the result is cached on first read.

### Projected value (`$`)

All three macros expose the underlying factory as a projected value via `$`:

```swift
class MyService {
    @Injected(Container.logger) var logger: Logger

    func swapLogger() {
        $logger.register { FileLogger() }
    }
}
```

### Comparison table

| Macro | Resolves when | Subsequent reads | Stores value | Best for |
|---|---|---|---|---|
| `@Injected` | Every property access | Re-resolve each time | No | Always-fresh values, lightweight factories |
| `@ConstructorInjected` | Object init | Return stored value | Yes | Dependencies needed for the object's lifetime |
| `@LazyInjected` | First property access | Return cached value | Yes (after first read) | Expensive init you want to defer |

---

## Hierarchical Containers

Create nested container scopes with `withNestedContainer`. Child containers inherit registrations from their parent but can override them without affecting the parent.

```swift
// Parent scope
Container.logger.register { ConsoleLogger() }

withNestedContainer {
    // Override in child scope
    Container.logger.register { FileLogger() }
    Container.logger() // -> FileLogger

    withNestedContainer {
        // Grandchild inherits from child
        Container.logger() // -> FileLogger

        // Override in grandchild
        Container.logger.register { RemoteLogger() }
        Container.logger() // -> RemoteLogger
    }

    // Child is unaffected
    Container.logger() // -> FileLogger
}

// Parent is unaffected
Container.logger() // -> ConsoleLogger
```

### Manual registration stacking

You can also push/pop registrations manually using `register` and `popRegistration`:

```swift
Container.logger.register { FileLogger() }
Container.logger() // -> FileLogger

Container.logger.popRegistration()
Container.logger() // -> back to previous registration
```

Registrations are LIFO (last-in, first-out). `popRegistration()` removes the most recent override.

---

## Detached Tasks and Context Propagation

The current container propagates automatically through structured concurrency (child tasks, task groups, etc.). However, **detached tasks** (`Task.detached`) lose this context. Use `withContainer` to re-apply it:

```swift
let container = Container.current

Task.detached {
    // Container.current would be Container.default here!

    withContainer(container) {
        // Container.current is now the correct container
        let logger = Container.logger()
    }
}
```

---

## Testing

### `withTestContainer`

Wrap each test in `withTestContainer` to get an isolated container that cannot interfere with other tests, even when running concurrently:

```swift
@Test func myTest() {
    withTestContainer {
        Container.logger.register { MockLogger() }
        // All resolutions inside this block use the test container
    }
    // Test container is torn down -- registrations are gone
}
```

`withTestContainer` works with both sync and async tests:

```swift
@Test func asyncTest() async {
    await withTestContainer {
        Container.networkClient.register { MockClient() }
        let result = await fetchData()
        #expect(result == .success)
    }
}
```

**What happens under the hood:**
1. A `TestContainer` (child of the current container) is created
2. It is set as the current container via `ServiceContext`
3. `Container.default.fatalErrorOnResolve` is set to `true` -- any resolution that escapes the test container and hits the default container will crash with a clear error message
4. When the block exits, everything is cleaned up

### Unregistered behavior

By default, resolving a factory that was **not** registered in the test container triggers a `fatalError` with a detailed message (file, line, function of both the resolution site and the test container creation site). This catches missing test doubles immediately:

```swift
// This will crash with:
// "Dependency: Logger on factory: ... not registered!
//  Called from MyService.swift:42 in placeOrder().
//  Test container created at MyServiceTests.swift:10 in testPlaceOrder()"
withTestContainer {
    let service = OrderService() // OrderService uses @Injected(Container.logger)
    service.placeOrder()         // BOOM -- Container.logger not registered
}
```

### Leaked resolution detection

When async work spawned inside `withTestContainer` outlives the block, it can resolve dependencies against a dead test container. The framework detects this and takes action:

```swift
withTestContainer {
    // This task is NOT awaited -- it will outlive the test container
    Task { await Container.session() }
}
// The leaked resolution is detected here
```

Three built-in behaviors are available:

| Type | Behavior |
|---|---|
| `DefaultLeakedResolutionBehavior` | Checks `DI_BEST_EFFORT_LEAK_RESOLUTION` env var. If `"true"`, uses best-effort. Otherwise crashes. **(default)** |
| `BestEffortLeakedResolutionBehavior` | Cancels the leaking task, returns `nil` for optionals, falls back to the production resolver as a last resort |
| `CrashLeakedResolutionBehavior` | Always crashes with a detailed error message |

Specify a behavior explicitly:

```swift
withTestContainer(leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
    // ...
}
```

Or set the environment variable `DI_BEST_EFFORT_LEAK_RESOLUTION=true` in your test scheme to use best-effort globally.

### Composable test defaults

For libraries or large features, define reusable sets of test doubles using `TestDefault` and `TestDefaults`:

```swift
// A single test default
let loggerDefault = TestDefault {
    Container.logger.testValue { MockLogger() }
}

// A group of test defaults
extension TestDefaults {
    static let networkingDefaults = TestDefaults {
        TestDefault { Container.httpClient.testValue { MockHTTPClient() } }
        TestDefault { Container.session.testValue { MockSession() } }
    }
}
```

Compose defaults together:

```swift
extension TestDefaults {
    static let featureDefaults = TestDefaults {
        .networkingDefaults
        TestDefault { Container.analytics.testValue { NoopAnalytics() } }
    }
}
```

Apply them to a test container:

```swift
@Test func featureTest() {
    withTestContainer(defaults: .featureDefaults) {
        // All defaults are pre-registered
        let client = Container.httpClient() // -> MockHTTPClient
    }
}
```

You can also pass an array of defaults:

```swift
withTestContainer(defaults: [.networkingDefaults, .analyticsDefaults]) {
    // Both sets of defaults are registered
}
```

This lets library authors ship test doubles alongside their DI registrations, and feature teams compose them without boilerplate.

---

## Architecture

### Component overview

```
Container                    The resolution context; holds per-factory storage
  |-- Storage<Factory>       LIFO registration stack per factory
  |-- parent: Container?     Parent for hierarchical fallback
  '-- fatalErrorOnResolve    Atomic flag for test leak detection

Factory (Sync|SyncThrowing|Async|AsyncThrowing)
  |-- resolver               The default production closure
  |-- scope                  Lifetime strategy (unique/cached/shared)
  |-- register()             Push an override onto the current container's stack
  |-- popRegistration()      Pop the most recent override
  '-- callAsFunction()       Resolve through Container.current

Scope
  |-- UniqueScope            Always calls the resolver
  |-- CachedScope            Per-container strong cache + async task deduplication
  '-- SharedScope            Per-container weak cache + async task deduplication

TestContainer (extends Container)
  |-- executingTest           Atomic flag for leak detection window
  |-- unregisteredBehavior    What to do when a factory has no test double
  '-- leakedResolutionBehavior  What to do when resolution escapes test scope

Macros (@Injected, @LazyInjected, @ConstructorInjected)
  '-- Expand to resolver types + computed property + projected value
```

### Resolution flow

When you call `factory()` or access an `@Injected` property:

1. **Find the current container** via `ServiceContext` (falls back to `Container.default`)
2. **Check the container's registration stack** for this factory
3. If found, **apply the scope** (unique returns a new instance; cached/shared check the cache first)
4. If not found, **walk up to the parent container** and repeat
5. If no container has an override, **use the factory's default resolver** with its scope
6. In a `TestContainer`, if no registration exists and `executingTest` is false, trigger **leaked resolution behavior**
7. In a `TestContainer`, if no registration exists and `executingTest` is true, trigger **unregistered behavior** (default: `fatalError`)

### Thread safety

| Mechanism | Where used |
|---|---|
| `NSRecursiveLock` | Container storage, registration stacks, scope caches, `LazyInjectedResolver` |
| `ManagedAtomic<Bool>` | `fatalErrorOnResolve`, `executingTest`, `useProduction` flags |
| `ManagedAtomic<Int>` | Ref-counting for concurrent `withTestContainer` entry/exit |
| `@globalActor DIActor` | Serializing async cached/shared scope resolution (prevents duplicate tasks) |
| `ServiceContext` (task-local) | Propagating the current container through structured concurrency |

### How caching works with containers

Caches (`StrongCache`, `WeakCache`) store entries **per container identity** (`ObjectIdentifier`). This means:

- Each `withTestContainer` block gets its own cache entries
- Concurrent tests with `.cached` scope never share instances
- In production, `Container.default` cache entries persist as expected
- Inside a `TestContainer`, parent cache lookups are **disabled** to prevent test pollution

When you call `factory.register(...)` on a factory with `.cached` or `.shared` scope, the cache is automatically cleared so the next resolution uses the new resolver.

---

## API Reference

### Free functions

| Function | Description |
|---|---|
| `Factory(scope:resolver:)` | Create a factory. The closure signature determines the factory type. |
| `withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:operation:)` | Run a test in an isolated container. Sync and async overloads. |
| `withNestedContainer(operation:)` | Create a child container scope. Sync and async overloads. |
| `withContainer(_:operation:)` | Re-apply a container context (for detached tasks). Sync and async overloads. |

### `SyncFactory<T>` / `SyncThrowingFactory<T>` / `AsyncFactory<T>` / `AsyncThrowingFactory<T>`

| Method | Description |
|---|---|
| `callAsFunction()` | Resolve the dependency through `Container.current` |
| `register(_:)` | Push a new resolver onto the current container's stack and clear scope cache |
| `popRegistration()` | Remove the most recent resolver from the stack |
| `useProduction()` | Mark this factory to always use its default resolver (bypasses test overrides) |
| `testValue(_:)` | Create a `FactoryDefault` for use with `TestDefault` / `TestDefaults` |

### `Container`

| Property/Method | Description |
|---|---|
| `Container.current` | The container in the current async context |
| `Container.default` | The global default container |

### Scopes

| Scope | Description |
|---|---|
| `.unique` | New instance per resolution (default) |
| `.cached` | Strong-cached per container, async-deduplicated |
| `.shared` | Weak-cached per container, async-deduplicated; recreated when all references are released |

### Macros

| Macro | Wrapped value type | Resolves |
|---|---|---|
| `@Injected(syncFactory)` | `T` | Every access |
| `@Injected(syncThrowingFactory)` | `Result<T, any Error>` | Every access |
| `@Injected(asyncFactory)` | `Task<T, Never>` | Every access |
| `@Injected(asyncThrowingFactory)` | `Task<T, any Error>` | Every access |
| `@ConstructorInjected(syncFactory)` | `T` | Once at init |
| `@ConstructorInjected(syncThrowingFactory)` | `Result<T, any Error>` | Once at init |
| `@ConstructorInjected(asyncFactory)` | `Task<T, Never>` | Once at init |
| `@ConstructorInjected(asyncThrowingFactory)` | `Task<T, any Error>` | Once at init |
| `@LazyInjected(syncFactory)` | `T` | First access |
| `@LazyInjected(syncThrowingFactory)` | `Result<T, any Error>` | First access |
| `@LazyInjected(asyncFactory)` | `Task<T, Never>` | First access |
| `@LazyInjected(asyncThrowingFactory)` | `Task<T, any Error>` | First access |

### Test defaults

| Type | Description |
|---|---|
| `FactoryDefault` | A single factory-to-resolver binding, created by `factory.testValue { ... }` |
| `TestDefault` | A group of `FactoryDefault`s, built with `@TestDefaultBuilder` |
| `TestDefaults` | A composable group of `TestDefault` and/or other `TestDefaults`, built with `@TestDefaultsBuilder`. Also `ExpressibleByArrayLiteral`. |

### Leaked resolution behaviors

| Type | Behavior |
|---|---|
| `DefaultLeakedResolutionBehavior` | Crashes unless `DI_BEST_EFFORT_LEAK_RESOLUTION=true` env var is set |
| `BestEffortLeakedResolutionBehavior` | Cancels task, returns nil for optionals, falls back to production |
| `CrashLeakedResolutionBehavior` | Always crashes |
| Custom | Conform to `LeakedResolutionBehavior` protocol |

---

## License

See [LICENSE](LICENSE) for details.
