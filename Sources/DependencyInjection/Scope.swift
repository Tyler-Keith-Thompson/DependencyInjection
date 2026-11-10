//
//  Scope.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Foundation

/// A global actor used to serialize async resolution for cached and shared scopes.
///
/// This prevents duplicate async tasks from running concurrently when multiple
/// callers resolve the same cached/shared factory at the same time.
@globalActor
actor DIActor: GlobalActor {
    static let shared = DIActor()
}

protocol ScopeWithCache {
    var cache: any Cache { get }
}

/// The base class for dependency lifetime strategies.
///
/// A scope controls how and when a factory's resolver is called and whether the
/// result is cached. The framework provides three built-in scopes:
///
/// | Scope | Behavior |
/// |---|---|
/// | ``unique`` | New instance every resolution (default) |
/// | ``cached`` | Created once, held with a strong reference |
/// | ``shared`` | Created once, held with a weak reference; recreated when deallocated |
///
/// Specify a scope when creating a factory:
///
/// ```swift
/// extension Container {
///     static let analytics = Factory(scope: .cached) { AnalyticsService() }
///     static let session   = Factory(scope: .shared) { Session() }
/// }
/// ```
///
/// You can subclass `Scope` to create custom lifetime strategies.
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
    /// A scope that creates a new instance on every resolution. This is the default.
    public static var unique: UniqueScope { UniqueScope() }

    /// A scope that creates the instance once and caches it with a strong reference.
    ///
    /// The cached instance lives for the lifetime of its container. Each container
    /// (including test containers) gets its own cache entry, so cached singletons in
    /// tests never collide with production or other tests.
    ///
    /// For async factories, concurrent resolutions are deduplicated -- only one task
    /// runs the resolver and all callers await the same result.
    public static var cached: CachedScope { CachedScope() }

    /// A scope that creates the instance once and caches it with a weak reference.
    ///
    /// The instance is kept alive as long as at least one external reference exists.
    /// Once all references are released, the next resolution creates a new instance.
    ///
    /// For async factories, concurrent resolutions are deduplicated just like ``cached``.
    public static var shared: SharedScope { SharedScope() }
}

/// A scope that creates a new instance on every resolution.
///
/// This is the default scope. No caching is performed.
public final class UniqueScope: Scope, @unchecked Sendable { }

/// A scope that caches the resolved instance with a strong reference.
///
/// Once resolved, the same instance is returned for all subsequent resolutions
/// within the same container. The cache is per-container, so test containers
/// get their own isolated cache entries.
///
/// For async factories, resolution is serialized via ``DIActor`` and concurrent
/// callers are deduplicated -- only one task runs the resolver.
public final class CachedScope: Scope, ScopeWithCache, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    /// The strong cache backing this scope.
    public let cache: any Cache = StrongCache()
    private var taskStorage = [ObjectIdentifier: Any]()

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

    @DIActor override func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
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

    @DIActor override func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
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

/// A scope that caches the resolved instance with a weak reference.
///
/// The instance is kept alive as long as at least one external reference exists.
/// When all references are released, the cached entry is cleared and the next
/// resolution creates a fresh instance.
///
/// This is useful for shared resources that should be deallocated when no longer in use.
public final class SharedScope: Scope, ScopeWithCache, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    /// The weak cache backing this scope.
    public let cache: any Cache = WeakCache()
    private var taskStorage = [ObjectIdentifier: Any]()

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

    @DIActor override func resolve<D>(resolver: @escaping AsyncFactory<D>.Resolver) async -> D {
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

    @DIActor override func resolve<D>(resolver: @escaping AsyncThrowingFactory<D>.Resolver) async throws -> D {
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
