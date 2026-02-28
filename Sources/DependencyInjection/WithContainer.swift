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
/// lose it, such as detached tasks or GCD blocks:
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
