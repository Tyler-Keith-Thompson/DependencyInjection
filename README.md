# DependencyInjection

Dependency injection for Swift 6. Factories can be sync or async, throwing or not; macros inject them into properties; and each test gets its own container, so tests that run in parallel never see each other's test doubles.

**[Documentation](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/)**

## Features

- Built for Swift 6 strict concurrency: everything is `Sendable`.
- Four kinds of factory: sync, sync throwing, async and async throwing.
- Three scopes: unique, cached and shared (weak).
- `@Injected`, `@LazyInjected` and `@ConstructorInjected` macros.
- Nested containers that fall back to their parent.
- Test containers that stay isolated when tests run concurrently.
- Detection of async work that escapes a test and resolves after it ends.
- Debug builds stop on a dependency cycle and print the whole chain.
- Reusable, composable sets of test doubles.

## Requirements

- Swift 6.4+
- iOS 17+ / macOS 13+ / watchOS 10+ / tvOS 17+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/DependencyInjection.git", from: "1.0.0"),
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "DependencyInjection", package: "DependencyInjection"),
    ]
)
```

## Quick start

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

## Guides

The full guide lives in the DocC documentation:

- [Factories, containers and scopes](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/coreconcepts): the four factory types, the current container, and `.unique`, `.cached` and `.shared`.
- [Injection macros](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/injectionmacros): when each macro resolves, and which container it resolves in.
- [Hierarchical containers](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/hierarchicalcontainers): overriding registrations in a nested scope.
- [Dependency cycles](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/dependencycycles): what debug builds report, and what they can't see.
- [Detached tasks and context propagation](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/contextpropagation): `Task.detached`, server request handlers and other callbacks.
- [Testing](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/testing): test containers, missing test doubles, leaked resolutions and shared test defaults.
- [Architecture](https://tyler-keith-thompson.github.io/DependencyInjection/DependencyInjection/documentation/dependencyinjection/architecture): how resolution works and what keeps it thread-safe.

The API reference is there too.

## License

Apache 2.0. See [LICENSE](LICENSE).

`Sources/DispatchInterpose/simple_rebind.c` is derived from [fishhook](https://github.com/facebook/fishhook) and keeps its BSD 3-clause notice.
