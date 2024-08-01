//
//  Factory.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

protocol _Factory: AnyObject, Hashable, Sendable {
    associatedtype Dependency
    associatedtype Resolver
    
    var resolver: Resolver { get }
    var scope: Scope { get }
    
    init(scope: Scope, resolver: Resolver)
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
    
    let resolver: Resolver
    let scope: Scope
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    public func callAsFunction() -> Dependency {
        Container.current.resolve(factory: self)
    }

    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
}

public final class SyncThrowingFactory<Dependency>: _Factory, @unchecked Sendable {
    public typealias Resolver = () throws -> Dependency
    let resolver: Resolver
    let scope: Scope
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    public func callAsFunction() throws -> Dependency {
        try Container.current.resolve(factory: self)
    }
    
    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
}

public final class AsyncFactory<Dependency: Sendable>: _Factory, @unchecked Sendable {
    public typealias Resolver = @Sendable () async -> Dependency
    let resolver: Resolver
    let scope: Scope
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    public func callAsFunction() async -> Dependency {
        await Container.current.resolve(factory: self)
    }
    
    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
    }
}

public final class AsyncThrowingFactory<Dependency: Sendable>: _Factory, @unchecked Sendable {
    public typealias Resolver = @Sendable () async throws -> Dependency
    
    let resolver: Resolver
    let scope: Scope
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }
    
    public func callAsFunction() async throws -> Dependency {
        try await Container.current.resolve(factory: self)
    }
    
    public func register(_ resolver: @escaping Resolver) {
        Container.current.addResolver(for: self, resolver: resolver)
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
