//
//  Factory.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Atomics

protocol _Factory: AnyObject, Hashable, Sendable {
    associatedtype Dependency
    associatedtype Resolver
    
    var shouldUseProduction: ManagedAtomic<Bool> { get }
    var resolver: Resolver { get }
    var scope: Scope { get }
    
    init(scope: Scope, resolver: Resolver)
    
    @discardableResult func useProduction() -> Self
}

extension _Factory {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs === rhs
    }
}

public final class SyncFactory<Dependency>: _Factory, @unchecked Sendable {
    public typealias Resolver = () -> Dependency
    
    public let scope: Scope
    let shouldUseProduction = ManagedAtomic<Bool>(false)
    let resolver: Resolver
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    @discardableResult public func useProduction() -> Self {
        shouldUseProduction.store(true, ordering: .sequentiallyConsistent)
        return self
    }

    public func callAsFunction() -> Dependency {
        if shouldUseProduction.load(ordering: .sequentiallyConsistent) {
            return resolver()
        } else {
            return Container.current.resolve(factory: self)
        }
    }

    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
    
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }
}

public final class SyncThrowingFactory<Dependency>: _Factory, @unchecked Sendable {
    public typealias Resolver = () throws -> Dependency
    public let scope: Scope
    let shouldUseProduction = ManagedAtomic<Bool>(false)
    let resolver: Resolver
    
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }

    @discardableResult public func useProduction() -> Self {
        shouldUseProduction.store(true, ordering: .sequentiallyConsistent)
        return self
    }

    public func callAsFunction() throws -> Dependency {
        if shouldUseProduction.load(ordering: .sequentiallyConsistent) {
            return try resolver()
        } else {
            return try Container.current.resolve(factory: self)
        }
    }
    
    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
    
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }
}

public final class AsyncFactory<Dependency: Sendable>: _Factory, @unchecked Sendable {
    public typealias Resolver = @Sendable () async -> Dependency
    public let scope: Scope
    let shouldUseProduction = ManagedAtomic<Bool>(false)
    let resolver: Resolver
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    @discardableResult public func useProduction() -> Self {
        shouldUseProduction.store(true, ordering: .sequentiallyConsistent)
        return self
    }

    public func callAsFunction() async -> Dependency {
        if shouldUseProduction.load(ordering: .sequentiallyConsistent) {
            return await resolver()
        } else {
            return await Container.current.resolve(factory: self)
        }
    }
    
    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
    
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }
}

public final class AsyncThrowingFactory<Dependency: Sendable>: _Factory, @unchecked Sendable {
    public typealias Resolver = @Sendable () async throws -> Dependency
    
    public let scope: Scope
    let shouldUseProduction = ManagedAtomic<Bool>(false)
    let resolver: Resolver
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    @discardableResult public func useProduction() -> Self {
        shouldUseProduction.store(true, ordering: .sequentiallyConsistent)
        return self
    }

    public func callAsFunction() async throws -> Dependency {
        if shouldUseProduction.load(ordering: .sequentiallyConsistent) {
            return try await resolver()
        } else {
            return try await Container.current.resolve(factory: self)
        }
    }
    
    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
    
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }
}

public func Factory<Dependency>(scope: Scope = .unique, resolver: @escaping () -> Dependency) -> SyncFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}

public func Factory<Dependency>(scope: Scope = .unique, resolver: @escaping () throws -> Dependency) -> SyncThrowingFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}

public func Factory<Dependency>(scope: Scope = .unique, resolver: @Sendable @escaping () async -> Dependency) -> AsyncFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}

public func Factory<Dependency>(scope: Scope = .unique, resolver: @Sendable @escaping () async throws -> Dependency) -> AsyncThrowingFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}
