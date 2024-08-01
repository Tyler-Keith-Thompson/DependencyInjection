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
    
    static var current: Container {
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
    var context = ServiceContext.topLevel
    context.container = Container(parent: Container.current)
    return try ServiceContext.withValue(context, operation: operation)
}

//@available(*, deprecated, message: "Prefer withNestedContainer(isolation:operation:)")
@_disfavoredOverload
@_unsafeInheritExecutor // Deprecated trick to avoid executor hop here; 6.0 introduces the proper replacement: #isolation
public func withNestedContainer<T>(operation: () async throws -> T) async rethrows -> T {
    var context = ServiceContext.topLevel
    context.container = Container(parent: Container.current)
    return try await ServiceContext.withValue(context, operation: operation)
}