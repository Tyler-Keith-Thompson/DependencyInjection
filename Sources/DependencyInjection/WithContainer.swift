//
//  WithContainer.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 11/28/24.
//

import ServiceContextModule

/// Executes a synchronous operation within the context of the given container reference.
///
/// Use this function to reapply a containerized context to tasks or operations
/// that would otherwise lose it, such as when detaching a task.
///
/// - Parameters:
///   - container: The `ContainerReference` whose context will be applied.
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

/// Executes an asynchronous operation within the context of the given container reference.
///
/// Use this function to reapply a containerized context to asynchronous tasks
/// that would otherwise lose it, such as `Task.detached`.
///
/// - Parameters:
///   - container: The `ContainerReference` whose context will be applied.
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
