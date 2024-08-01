//
//  Scope.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Foundation

@globalActor
actor DIActor: GlobalActor {
    static let shared = DIActor()
}

open class Scope {
    func resolve<D>(resolver: @escaping SyncFactory<D>.Resolver) -> D {
        resolver()
    }
    
    func resolve<D>(resolver: @escaping SyncThrowingFactory<D>.Resolver) throws -> D {
        try resolver()
    }
    
    @DIActor func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
        await resolver()
    }
    
    @DIActor func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
        try await resolver()
    }
}

extension Scope {
    public static var unique: UniqueScope { UniqueScope() }
    public static var cached: CachedScope { CachedScope() }
}

public final class UniqueScope: Scope, @unchecked Sendable { }

public final class CachedScope: Scope, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let cache = StrongCache()
    var task: Any?
    
    override func resolve<D>(resolver: @escaping SyncFactory<D>.Resolver) -> D {
        if let result = cache() as? D {
            return result
        }
        let resolved = resolver()
        cache.register(resolved)
        return resolved
    }
    
    override func resolve<D>(resolver: @escaping SyncThrowingFactory<D>.Resolver) throws -> D {
        if let result = cache() as? D {
            return result
        }
        let resolved = try resolver()
        cache.register(resolved)
        return resolved
    }
    
    @DIActor override func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
        if cache.hasValue, let result = cache() as? D {
            return result
        }
        if let task = lock.withLock({ self.task }) as? Task<D, Never> {
            return await task.value
        }
        defer { lock.withLock { self.task = nil } }
        let task = Task { [weak self] in
            let resolved = await resolver()
            if let self {
                self.lock.withLock {
                    self.cache.register(resolved)
                }
            }
            return resolved
        }
        lock.withLock { self.task = task }
        return await task.value
    }
    
    @DIActor override func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
        if cache.hasValue, let result = cache() as? D {
            return result
        }
        if let task = lock.withLock({ self.task }) as? Task<D, any Error> {
            return try await task.value
        }
        defer { lock.withLock { self.task = nil } }
        let task = Task { [weak self] in
            let resolved = try await resolver()
            if let self {
                self.lock.withLock {
                    self.cache.register(resolved)
                }
            }
            return resolved
        }
        lock.withLock { self.task = task }
        return try await task.value
    }
}

extension NSLock {
    func withLock<ReturnValue>(_ body: () throws -> ReturnValue) rethrows -> ReturnValue {
        lock()
        defer { unlock() }
        return try body()
    }
}
