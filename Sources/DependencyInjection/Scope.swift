//
//  Scope.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Foundation

protocol ScopeWithCache {
    var cache: any Cache { get }
}

open class Scope: @unchecked Sendable {
    func resolve<D>(resolver: @escaping SyncFactory<D>.Resolver) -> D {
        resolver()
    }
    
    func resolve<D>(resolver: @escaping SyncThrowingFactory<D>.Resolver) throws -> D {
        try resolver()
    }
    
    func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
        await resolver()
    }
    
    func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
        try await resolver()
    }
}

extension Scope {
    public static var unique: UniqueScope { UniqueScope() }
    public static var cached: CachedScope { CachedScope() }
    public static var shared: SharedScope { SharedScope() }
}

public final class UniqueScope: Scope, @unchecked Sendable { }

public final class CachedScope: Scope, ScopeWithCache, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    public let cache: any Cache = StrongCache()
    private var taskStorage = [ObjectIdentifier: Any]()
    
    func clearTaskStorage(for container: Container) {
        let containerId = ObjectIdentifier(container)
        lock.protect {
            taskStorage[containerId] = nil
        }
    }
    
    override func resolve<D>(resolver: @escaping SyncFactory<D>.Resolver) -> D {
        lock.protect {
            if cache.hasValue, let result = cache() as? D {
                return result
            }
            let resolved = resolver()
            cache.register(resolved)
            return resolved
        }
    }
    
    override func resolve<D>(resolver: @escaping SyncThrowingFactory<D>.Resolver) throws -> D {
        try lock.protect {
            if cache.hasValue, let result = cache() as? D {
                return result
            }
            let resolved = try resolver()
            cache.register(resolved)
            return resolved
        }
    }
    
    override func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
        if cache.hasValue, let result = cache() as? D {
            return result
        }
        let containerId = ObjectIdentifier(Container.current)
        if let task = lock.protect({ self.taskStorage[containerId] }) as? Task<D, Never> {
            return await task.value
        }
        defer { lock.protect { self.taskStorage[containerId] = nil } }
        let task = Task { [weak self] in
            let resolved = await resolver()
            if let self {
                self.lock.protect {
                    self.cache.register(resolved)
                }
            }
            return resolved
        }
        lock.protect { self.taskStorage[containerId] = task }
        return await task.value
    }
    
    override func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
        if cache.hasValue, let result = cache() as? D {
            return result
        }
        let containerId = ObjectIdentifier(Container.current)
        if let task = lock.protect({ self.taskStorage[containerId] }) as? Task<D, any Error> {
            return try await task.value
        }
        defer { lock.protect { self.taskStorage[containerId] = nil } }
        let task = Task { [weak self] in
            let resolved = try await resolver()
            if let self {
                self.lock.protect {
                    self.cache.register(resolved)
                }
            }
            return resolved
        }
        lock.protect { self.taskStorage[containerId] = task }
        return try await task.value
    }
}

public final class SharedScope: Scope, ScopeWithCache, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    public let cache: any Cache = WeakCache()
    private var taskStorage = [ObjectIdentifier: Any]()
    
    func clearTaskStorage(for container: Container) {
        let containerId = ObjectIdentifier(container)
        lock.protect {
            taskStorage[containerId] = nil
        }
    }
    
    override func resolve<D>(resolver: @escaping SyncFactory<D>.Resolver) -> D {
        lock.protect {
            if cache.hasValue, let result = cache() as? D {
                return result
            }
            let resolved = resolver()
            cache.register(resolved)
            return resolved
        }
    }
    
    override func resolve<D>(resolver: @escaping SyncThrowingFactory<D>.Resolver) throws -> D {
        try lock.protect {
            if let result = cache() as? D {
                return result
            }
            let resolved = try resolver()
            cache.register(resolved)
            return resolved
        }
    }
    
    override func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
        if cache.hasValue, let result = cache() as? D {
            return result
        }
        let containerId = ObjectIdentifier(Container.current)
        if let task = lock.protect({ self.taskStorage[containerId] }) as? Task<D, Never> {
            return await task.value
        }
        defer { lock.protect { self.taskStorage[containerId] = nil } }
        let task = Task { [weak self] in
            let resolved = await resolver()
            if let self {
                self.lock.protect {
                    self.cache.register(resolved)
                }
            }
            return resolved
        }
        lock.protect { self.taskStorage[containerId] = task }
        return await task.value
    }
    
    override func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
        if cache.hasValue, let result = cache() as? D {
            return result
        }
        let containerId = ObjectIdentifier(Container.current)
        if let task = lock.protect({ self.taskStorage[containerId] }) as? Task<D, any Error> {
            return try await task.value
        }
        defer { lock.protect { self.taskStorage[containerId] = nil } }
        let task = Task { [weak self] in
            let resolved = try await resolver()
            if let self {
                self.lock.protect {
                    self.cache.register(resolved)
                }
            }
            return resolved
        }
        lock.protect { self.taskStorage[containerId] = task }
        return try await task.value
    }
}

extension NSRecursiveLock {
    func protect<T>(_ instructions: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try instructions()
    }
}
