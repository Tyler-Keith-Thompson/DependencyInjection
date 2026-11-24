# Detached tasks and context propagation

Carry the current container into work that structured concurrency doesn't reach.

## Detached tasks

The current container follows structured concurrency: child tasks, task groups and `async let` all see it. A `Task.detached` doesn't, and neither does work a framework runs on its own tasks or threads; there, ``Container/current`` is the default container. Capture the container and apply it again with ``withContainer(_:operation:)``:

```swift
let container = Container.current

Task.detached {
    withContainer(container) {
        let logger = Container.logger() // resolves in `container`
    }
}
```

## Server request handlers

Server frameworks such as Vapor or SwiftNIO run each request handler on an event-loop task, not in the task that set up the routes. The handler loses the container even when the whole server started inside `withContainer` or `withTestContainer`. A resolve in the handler then goes to the default container, and in a test it hits the "outside any container" crash.

Capture ``Container/current`` when you build the routes and wrap each handler in `withContainer`:

```swift
func routes(_ app: Application) {
    let container = Container.current
    app.get("x") { req in
        await withContainer(container) { await Container.service().handle(req) }
    }
}
```

It applies to every factory type and scope, since the handler resolves in whichever container is current when it runs. Use the same pattern for any callback a library calls from its own threads or tasks.
