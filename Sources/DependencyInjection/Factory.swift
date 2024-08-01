//
//  Factory.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

protocol _Factory: AnyObject, Hashable {
    associatedtype Dependency
    associatedtype Resolver
    
    var resolver: Resolver { get }
    
    init(resolver: Resolver)
}

extension _Factory {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs === rhs
    }
}

public final class SyncFactory<Dependency>: _Factory {
    public typealias Resolver = () -> Dependency
    
    let resolver: () -> Dependency
    init(resolver: @escaping () -> Dependency) {
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

public final class SyncThrowingFactory<Dependency>: _Factory {
    public typealias Resolver = () throws -> Dependency
    let resolver: () throws -> Dependency
    init(resolver: @escaping () throws -> Dependency) {
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

public final class AsyncFactory<Dependency>: _Factory {
    public typealias Resolver = @Sendable () async -> Dependency
    let resolver: @Sendable () async -> Dependency
    init(resolver: @Sendable  @escaping () async -> Dependency) {
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

public final class AsyncThrowingFactory<Dependency>: _Factory {
    public typealias Resolver = @Sendable () async throws -> Dependency
    
    let resolver: @Sendable () async throws -> Dependency
    init(resolver: @Sendable @escaping () async throws -> Dependency) {
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

public func Factory<Dependency>(resolver: @escaping () -> Dependency) -> SyncFactory<Dependency> {
    .init(resolver: resolver)
}

public func Factory<Dependency>(resolver: @escaping () throws -> Dependency) -> SyncThrowingFactory<Dependency> {
    .init(resolver: resolver)
}

public func Factory<Dependency>(resolver: @Sendable @escaping () async -> Dependency) -> AsyncFactory<Dependency> {
    .init(resolver: resolver)
}

public func Factory<Dependency>(resolver: @Sendable @escaping () async throws -> Dependency) -> AsyncThrowingFactory<Dependency> {
    .init(resolver: resolver)
}
