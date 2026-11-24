# Testing

Give each test its own container, catch missing test doubles and work that escapes the test, and share sets of test doubles.

## Test containers

Wrap each test in ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)``. The block gets its own container, which other tests can't touch even when they run in parallel:

```swift
@Test func placesOrder() {
    withTestContainer {
        Container.logger.register { MockLogger() }
        // Every resolution in here uses the test container.
    }
    // The test container is gone, and its registrations with it.
}
```

It works in async tests too:

```swift
@Test func fetchesData() async {
    await withTestContainer {
        Container.networkClient.register { MockClient() }
        let result = await fetchData()
        #expect(result == .success)
    }
}
```

When the block starts, it:

1. creates a test container as a child of the current container;
2. makes it the current container through `ServiceContext`;
3. makes the default container crash on any resolution, with a message saying why.

Everything is undone when the block exits.

While any test container is open, every test in the binary that resolves dependencies must use `withTestContainer`. Step 3 applies to the whole process, and tests run in parallel, so a test that resolves with no container at all crashes whenever another test's block happens to be open. The crash message names both causes (a test without `withTestContainer`, or work that escaped its container, such as a `Task.detached` or a `Task` that outlived its block). It also lists the file, line and function of every test container open at the time, so you can see which tests were running.

## Missing test doubles

Resolving a factory that has no registration in the test container calls `fatalError` by default (see ``UnregisteredBehavior``). The message gives the file, line and function of both the resolution and the test container, so a missing test double shows up at once:

```swift
// Crashes with:
// "Dependency: Logger on factory: ... not registered!
//  Called from MyService.swift:42 in placeOrder().
//  Test container created at MyServiceTests.swift:10 in testPlaceOrder()"
withTestContainer {
    let service = OrderService() // uses @Injected(Container.logger)
    service.placeOrder()         // Container.logger has no registration
}
```

## Using real resolvers in a test

Two calls let a factory resolve without a test registration. Each applies only to the current test container and respects the factory's scope, and the later call wins:

```swift
withTestContainer {
    Container.dateFormatter.useProduction()   // the production resolver
    Container.logger.useParentContainer()     // the enclosing container's registration
}
```

`useParentContainer()` is for registrations made outside the test container, such as a `withNestedContainer` set up around several tests. It takes the enclosing container's resolver, not its instance, and runs it inside the test container. So a `.cached` or `.shared` value is cached in the test container (each test gets its own, not the one the enclosing container holds). The resolver's own dependencies resolve in the test container too, so they need test registrations or their own `useProduction()` or `useParentContainer()`. If nothing above the test container registers the factory, it falls back to production.

## Leaked resolutions

Async work started inside `withTestContainer` can outlive the block and then resolve a dependency against a test container that's gone:

```swift
withTestContainer {
    // Not awaited, so it outlives the test container.
    Task { await Container.session() }
}
// The leaked resolution is caught here.
```

What happens next is up to a ``LeakedResolutionBehavior``:

| Type | Behavior |
|---|---|
| ``DefaultLeakedResolutionBehavior`` | Uses best effort when the `DI_BEST_EFFORT_LEAK_RESOLUTION` environment variable is `"true"`, and crashes otherwise. This is the default. |
| ``BestEffortLeakedResolutionBehavior`` | Cancels the leaking task, returns `nil` for optionals, and falls back to the production resolver as a last resort |
| ``CrashLeakedResolutionBehavior`` | Always crashes with a detailed message |

Pass one explicitly:

```swift
withTestContainer(leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
    // ...
}
```

Or set `DI_BEST_EFFORT_LEAK_RESOLUTION=true` in your test scheme to use best effort everywhere. You can also write your own conforming type.

## Shared test doubles

For a library or a large feature, define reusable sets of test doubles with ``TestDefault`` and ``TestDefaults``. A factory's `testValue(_:)` makes a ``FactoryDefault``:

```swift
let loggerDefault = TestDefault {
    Container.logger.testValue { MockLogger() }
}

extension TestDefaults {
    static let networkingDefaults = TestDefaults {
        TestDefault { Container.httpClient.testValue { MockHTTPClient() } }
        TestDefault { Container.session.testValue { MockSession() } }
    }
}
```

Groups compose:

```swift
extension TestDefaults {
    static let featureDefaults = TestDefaults {
        .networkingDefaults
        TestDefault { Container.analytics.testValue { NoopAnalytics() } }
    }
}
```

Apply them when you open the test container, as one group or an array:

```swift
@Test func feature() {
    withTestContainer(defaults: .featureDefaults) {
        let client = Container.httpClient() // MockHTTPClient
    }
}

withTestContainer(defaults: [.networkingDefaults, .analyticsDefaults]) {
    // Both sets are registered.
}
```

A library can ship its test doubles next to its registrations this way, and feature teams can combine them.
