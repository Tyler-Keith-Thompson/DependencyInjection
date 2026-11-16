//
//  WithContainer.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 11/28/24.
//

import ServiceContextModule

/// Executes a synchronous operation within the context of the given container.
///
/// Use this function to reapply container context to operations that would otherwise
/// lose it, such as detached tasks, GCD blocks, or the request handlers of a server framework
/// (Vapor, SwiftNIO) that runs them on its own event-loop tasks:
///
/// ```swift
/// let container = Container.current
/// Task.detached {
///     withContainer(container) {
///         let logger = Container.logger() // resolves in the correct container
///     }
/// }
/// ```
///
/// - Parameters:
///   - container: The container whose context will be applied.
///   - operation: A synchronous operation to execute within the container's context.
/// - Returns: The result of the operation.
/// - Throws: Any error thrown by the operation.
public func withContainer<T>(
    _ container: Container,
    operation: () throws -> T
) rethrows -> T {
    var context = ServiceContext.inUse
    context.container = container
    return try ServiceContext.withValue(context, operation: operation)
}

/// Executes an asynchronous operation within the context of the given container.
///
/// Use this function to reapply container context to asynchronous operations that
/// would otherwise lose it, such as `Task.detached`:
///
/// ```swift
/// let container = Container.current
/// Task.detached {
///     await withContainer(container) {
///         let session = await Container.session()
///     }
/// }
/// ```
///
/// Server request handlers (Vapor, SwiftNIO) lose it too: the framework runs each handler on
/// its own event-loop task, not in the task that configured the routes. Capture the container
/// when the routes are built and apply it in every handler:
///
/// ```swift
/// func routes(_ app: Application) {
///     let container = Container.current
///     app.get("x") { req in
///         await withContainer(container) { await Container.service().handle(req) }
///     }
/// }
/// ```
///
/// - Parameters:
///   - container: The container whose context will be applied.
///   - isolation: The actor isolation context.
///   - operation: An asynchronous operation to execute within the container's context.
/// - Returns: The result of the operation.
/// - Throws: Any error thrown by the operation.
public func withContainer<T>(
    _ container: Container,
    isolation: isolated(any Actor)? = #isolation,
    operation: () async throws -> T
) async rethrows -> T {
    var context = ServiceContext.inUse
    context.container = container
    return try await ServiceContext.withValue(context, operation: operation)
}
