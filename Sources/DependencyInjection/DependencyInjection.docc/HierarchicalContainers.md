# Hierarchical containers

Override registrations in a nested scope without touching the enclosing one.

## Nested containers

``withNestedContainer(operation:)`` runs its closure in a child of the current container. The child sees its parent's registrations and can override them; the overrides go away when the closure returns.

```swift
Container.logger.register { ConsoleLogger() }

withNestedContainer {
    Container.logger.register { FileLogger() }
    Container.logger() // FileLogger

    withNestedContainer {
        Container.logger() // FileLogger, from the parent

        Container.logger.register { RemoteLogger() }
        Container.logger() // RemoteLogger
    }

    Container.logger() // FileLogger
}

Container.logger() // ConsoleLogger
```

## Stacking registrations by hand

`register(_:)` pushes a resolver onto the current container's stack for that factory, and `popRegistration()` removes the most recent one:

```swift
Container.logger.register { FileLogger() }
Container.logger() // FileLogger

Container.logger.popRegistration()
Container.logger() // the registration before it
```

Registering on a `.cached` or `.shared` factory clears its cache, so the next resolution uses the new resolver.
