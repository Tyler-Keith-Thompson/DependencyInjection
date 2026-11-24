# ``DependencyInjection``

Dependency injection for Swift 6, with async factories, injection macros and test containers that stay isolated when tests run in parallel.

## Overview

Declare each dependency once as a factory on `Container`. Resolve it by calling the factory or through a macro on a property, and swap in test doubles inside `withTestContainer`.

```swift
extension Container {
    static let logger = Factory { ConsoleLogger() as Logger }
}

class OrderService {
    @Injected(Container.logger) var logger: Logger
}
```

## Topics

### Essentials

- <doc:CoreConcepts>
- <doc:InjectionMacros>
- <doc:Testing>

### Containers and concurrency

- <doc:HierarchicalContainers>
- <doc:ContextPropagation>
- <doc:DependencyCycles>

### How it works

- <doc:Architecture>

### Factories

- ``Factory(scope:resolver:)->SyncFactory<Dependency>``
- ``SyncFactory``
- ``SyncThrowingFactory``
- ``AsyncFactory``
- ``AsyncThrowingFactory``

### Containers

- ``Container``
- ``withNestedContainer(operation:)``
- ``withContainer(_:operation:)``

### Scopes

- ``Scope``
- ``UniqueScope``
- ``CachedScope``
- ``SharedScope``
- ``Cache``

### Testing

- ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)``
- ``UnregisteredBehavior``
- ``LeakedResolutionBehavior``
- ``DefaultLeakedResolutionBehavior``
- ``BestEffortLeakedResolutionBehavior``
- ``CrashLeakedResolutionBehavior``
- ``TestDefault``
- ``TestDefaults``
- ``FactoryDefault``
