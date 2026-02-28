//
//  ServiceContext.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/31/24.
//

import ServiceContextModule

extension ServiceContext {
    static let `default` = ServiceContext.topLevel
    static var inUse: ServiceContext {
        .current ?? .default
    }
}

extension Container {
    static let `default` = Container()

    /// The container in the current async context.
    ///
    /// This property reads the container from Swift's `ServiceContext`, which
    /// propagates automatically through structured concurrency (child tasks,
    /// task groups, etc.). If no container has been set, it returns the global
    /// default container.
    ///
    /// `Container.current` is particularly useful when you need to capture and
    /// re-apply container context to detached tasks:
    ///
    /// ```swift
    /// let container = Container.current
    /// Task.detached {
    ///     withContainer(container) {
    ///         // Container.current is restored
    ///     }
    /// }
    /// ```
    public static var current: Container {
        ServiceContext.inUse.container
    }
}

struct ServiceContextContainerKey: ServiceContextKey {
    typealias Value = Container
}

extension ServiceContext {
    var container: Container {
        get {
            self[ServiceContextContainerKey.self] ?? .default
        } set {
            self[ServiceContextContainerKey.self] = newValue
        }
    }
}

/// Creates a child container and executes a synchronous operation within it.
///
/// The child container inherits all registrations from its parent but can override
/// them independently. When the operation completes, the child container is discarded.
///
/// ```swift
/// Container.logger.register { ConsoleLogger() }
///
/// withNestedContainer {
///     Container.logger.register { FileLogger() }
///     Container.logger() // -> FileLogger
/// }
///
/// Container.logger() // -> ConsoleLogger (parent unaffected)
/// ```
///
/// - Parameter operation: The operation to execute in the child container context.
/// - Returns: The result of the operation.
/// - Throws: Any error thrown by the operation.
public func withNestedContainer<T>(operation: () throws -> T) rethrows -> T {
    var context = ServiceContext.inUse
    context.container = Container(parent: Container.current)
    return try ServiceContext.withValue(context, operation: operation)
}

/// Creates a child container and executes an asynchronous operation within it.
///
/// The child container inherits all registrations from its parent but can override
/// them independently. When the operation completes, the child container is discarded.
///
/// - Parameters:
///   - isolation: The actor isolation context.
///   - operation: The async operation to execute in the child container context.
/// - Returns: The result of the operation.
/// - Throws: Any error thrown by the operation.
public func withNestedContainer<T>(isolation: isolated(any Actor)? = #isolation, operation: () async throws -> T) async rethrows -> T {
    var context = ServiceContext.inUse
    context.container = Container(parent: Container.current)
    return try await ServiceContext.withValue(context, operation: operation)
}
