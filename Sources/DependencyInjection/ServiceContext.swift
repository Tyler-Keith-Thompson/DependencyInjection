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
    
    /// A reference to a the currently in-use container, useful for
    /// propagation of contextual data across asynchronous boundaries.
    ///
    /// `ContainerReference` is particularly useful in cases where tasks lose their
    /// context (e.g., when using `Task.detached`). It provides a mechanism to
    /// explicitly pass and reapply a `Container` to such tasks.
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

public func withNestedContainer<T>(operation: () throws -> T) rethrows -> T {
    var context = ServiceContext.inUse
    context.container = Container(parent: Container.current)
    return try ServiceContext.withValue(context, operation: operation)
}

public func withNestedContainer<T>(isolation: isolated(any Actor)? = #isolation, operation: () async throws -> T) async rethrows -> T {
    var context = ServiceContext.inUse
    context.container = Container(parent: Container.current)
    return try await ServiceContext.withValue(context, operation: operation)
}
