# Factories, containers and scopes

Declare dependencies as factories, resolve them through the current container, and choose how long each instance lives.

## Factories

A factory registers one dependency. It wraps a closure that creates the dependency, and registers itself with the default container when it is created.

```swift
extension Container {
    static let logger = Factory { ConsoleLogger() as Logger }      // sync
    static let config = Factory { try loadConfig() }               // sync throwing
    static let session = Factory { await URLSession.shared }       // async
    static let database = Factory { try await Database.connect() } // async throwing
}
```

The closure's signature decides which factory type you get:

| Closure signature | Factory type |
|---|---|
| `() -> T` | ``SyncFactory`` |
| `() throws -> T` | ``SyncThrowingFactory`` |
| `() async -> T` | ``AsyncFactory`` |
| `() async throws -> T` | ``AsyncThrowingFactory`` |

Call a factory to resolve it:

```swift
let logger = Container.logger()
let config = try Container.config()
let session = await Container.session()
let db = try await Container.database()
```

## Containers

A ``Container`` is the context a resolution happens in. There is one global default container, and `ServiceContext` carries the current one through async call chains. ``Container/current`` returns the container for the running code, or the default container when nothing else is set.

Containers form a hierarchy. To resolve a factory, a container checks its own registrations first and then asks its parent. See <doc:HierarchicalContainers>.

## Scopes

A scope sets how long a resolved instance lives. Pass it when you create the factory:

```swift
static let logger = Factory(scope: .unique) { ConsoleLogger() }    // the default
static let analytics = Factory(scope: .cached) { AnalyticsService() }
static let session = Factory(scope: .shared) { Session() }
```

| Scope | Behavior | Use it for |
|---|---|---|
| ``Scope/unique`` | A new instance on every resolution | Stateless services, value types, or anything you want fresh each time |
| ``Scope/cached`` | Created once and held strongly | Singletons that live as long as the app |
| ``Scope/shared`` | Created once and held weakly; created again once every outside reference is gone | Shared resources that should be freed when nothing uses them |

Each container has its own cache. A test container caches its own instances, so a `.cached` singleton from one test never shows up in production code or in another test.

With `.cached` or `.shared`, concurrent resolutions of an async factory share one task: the resolver runs once and every caller awaits its result.
