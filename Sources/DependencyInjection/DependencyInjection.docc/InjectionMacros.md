# Injection macros

Inject dependencies into properties with `@Injected`, `@ConstructorInjected` and `@LazyInjected`.

## Overview

Each macro accepts all four factory types, and the property's type follows from the factory:

| Factory | Property type |
|---|---|
| ``SyncFactory`` | `T` |
| ``SyncThrowingFactory`` | `Result<T, any Error>` |
| ``AsyncFactory`` | `Task<T, Never>` |
| ``AsyncThrowingFactory`` | `Task<T, any Error>` |

```swift
@Injected(Container.config) var config: Result<Config, any Error>
@Injected(Container.session) var session: Task<URLSession, Never>

func fetch() async throws {
    let config = try config.get()
    let session = await session.value
    // ...
}
```

## Resolve on every read: @Injected

```swift
class FeatureViewModel {
    @Injected(Container.logger) var logger: Logger
}
```

Each read of `logger` resolves the factory again. Use it when you want the latest registration every time, or with a `.cached` or `.shared` factory, where resolving again is a cache hit.

## Resolve once at init: @ConstructorInjected

```swift
class PaymentProcessor {
    @ConstructorInjected(Container.gateway) var gateway: PaymentGateway
}
```

The dependency resolves when the owning object is created, and the object keeps that value for its whole life. For async factories the task starts at init and is cancelled in `deinit`.

## Resolve on first read: @LazyInjected

```swift
class ReportGenerator {
    @LazyInjected(Container.formatter) var formatter: DateFormatter
}
```

Nothing resolves until the property is first read. After that the object keeps the value, and reads are thread-safe.

Which container it resolves in depends on the factory:

- Sync and sync-throwing factories resolve at the first read, in whatever ``Container/current`` is at that read. That need not be the container the object was created in.
- Async and async-throwing factories start a `Task` at init. The task inherits the creating context, so it resolves in the container that was current at init. The first read only stores the task; awaiting `.value` waits for the result.

So an object created in one container and first read somewhere else (a SwiftUI `.task`, a callback, a `Task.detached`) gets its sync `@LazyInjected` dependencies from wherever the read happens. In the middle of a test, that can be the default container. If an object may be first used outside the context that created it, use `@ConstructorInjected`, or do the first read inside ``withContainer(_:operation:)``:

```swift
let container = Container.current
let generator = ReportGenerator()

Task.detached {
    withContainer(container) {
        _ = generator.formatter // resolves in `container`
    }
}
```

## The projected value

Each macro exposes its factory through `$`:

```swift
class MyService {
    @Injected(Container.logger) var logger: Logger

    func swapLogger() {
        $logger.register { FileLogger() }
    }
}
```

## Choosing a macro

| Macro | Resolves | Later reads | Keeps the value |
|---|---|---|---|
| `@Injected` | On every read | Resolve again | No |
| `@ConstructorInjected` | When the object is created | Return the stored value | Yes |
| `@LazyInjected` | Sync: on the first read, in the container current then. Async: at init, in the creating container | Return the stored value | Yes, after the first read |

## Types that inject each other

If two types inject each other with macros, give their factories explicit types:

```swift
static let a: SyncFactory<A> = Factory { A() }
```

Without them, the compiler reports "circular reference expanding peer macros". If the two really do resolve each other at run time, see <doc:DependencyCycles>.
