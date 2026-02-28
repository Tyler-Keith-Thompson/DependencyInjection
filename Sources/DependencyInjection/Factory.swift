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

/// A factory that produces dependencies using a synchronous, non-throwing resolver.
///
/// `SyncFactory` is the simplest factory type. Its resolver closure is called synchronously
/// and cannot throw. Use it for dependencies that can be created immediately without
/// error handling.
///
/// You typically create instances via the ``Factory(scope:resolver:)-6cibz`` function
/// and store them as static properties on ``Container``:
///
/// ```swift
/// extension Container {
///     static let logger = Factory { ConsoleLogger() as Logger }
/// }
/// ```
///
/// Factories are callable -- resolve a dependency by calling the factory directly:
///
/// ```swift
/// let logger = Container.logger()
/// ```
public final class SyncFactory<Dependency>: _Factory, @unchecked Sendable {
    /// The closure signature used to create the dependency.
    public typealias Resolver = () -> Dependency

    /// The scope that controls instance lifetime for this factory.
    public let scope: Scope
    let resolver: Resolver
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }

    /// Resolves and returns the dependency using the current container context.
    ///
    /// Resolution walks the container hierarchy: it checks the current container's
    /// registration stack first, then parent containers, and finally falls back to
    /// the factory's default resolver. The configured ``Scope`` is applied to control
    /// caching behavior.
    ///
    /// - Returns: The resolved dependency.
    public func callAsFunction(file: String = #file, line: UInt = #line, function: String = #function) -> Dependency {
        Container.current.resolve(factory: self, file: file, line: line, function: function)
    }

    /// Pushes a new resolver onto the current container's registration stack for this factory.
    ///
    /// The new resolver becomes the active resolver for subsequent resolutions in the
    /// current container context. If the factory uses a cached or shared scope, the
    /// cache is automatically cleared so the next resolution uses the new resolver.
    ///
    /// Registrations are LIFO (last-in, first-out). Use ``popRegistration()`` to remove
    /// the most recent override.
    ///
    /// ```swift
    /// Container.logger.register { FileLogger() as Logger }
    /// Container.logger() // -> FileLogger
    ///
    /// Container.logger.popRegistration()
    /// Container.logger() // -> back to previous resolver
    /// ```
    ///
    /// - Parameter resolver: The closure that creates the dependency.
    public func register(_ resolver: @escaping Resolver) {
        (scope as? ScopeWithCache)?.cache.clear()
        Container.current.addResolver(for: self, resolver: resolver)
    }

    /// Removes the most recent resolver override from the current container's registration stack.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }

    /// Marks this factory to bypass test overrides and always use its default production resolver.
    ///
    /// > Warning: This sets a global flag that persists across concurrent tests and can cause
    /// > test interference. Prefer using ``register(_:)`` with explicit test doubles instead.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func useProduction() -> Self {
        Container.current.useProduction(on: self)
        return self
    }
}

/// A factory that produces dependencies using a synchronous, throwing resolver.
///
/// `SyncThrowingFactory` works like ``SyncFactory`` but its resolver can throw.
/// When injected via the ``Injected(_:)-4jgny`` macro, the wrapped value type is
/// `Result<Dependency, any Error>`.
///
/// ```swift
/// extension Container {
///     static let config = Factory { try loadConfiguration() }
/// }
///
/// // Direct resolution
/// let config = try Container.config()
/// ```
public final class SyncThrowingFactory<Dependency>: _Factory, @unchecked Sendable {
    /// The closure signature used to create the dependency.
    public typealias Resolver = () throws -> Dependency
    /// The scope that controls instance lifetime for this factory.
    public let scope: Scope
    let resolver: Resolver

    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }

    /// Resolves and returns the dependency, or throws if the resolver fails.
    ///
    /// - Returns: The resolved dependency.
    /// - Throws: Any error thrown by the active resolver.
    public func callAsFunction(file: String = #file, line: UInt = #line, function: String = #function) throws -> Dependency {
        try Container.current.resolve(factory: self, file: file, line: line, function: function)
    }

    /// Pushes a new resolver onto the current container's registration stack.
    ///
    /// Clears cached values if this factory uses a cached or shared scope.
    ///
    /// - Parameter resolver: The closure that creates the dependency.
    public func register(_ resolver: @escaping Resolver) {
        (scope as? ScopeWithCache)?.cache.clear()
        Container.current.addResolver(for: self, resolver: resolver)
    }

    /// Removes the most recent resolver override from the current container's registration stack.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }

    /// Marks this factory to bypass test overrides and always use its default production resolver.
    ///
    /// > Warning: This sets a global flag that persists across concurrent tests and can cause
    /// > test interference. Prefer using ``register(_:)`` with explicit test doubles instead.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func useProduction() -> Self {
        Container.current.useProduction(on: self)
        return self
    }
}

/// A factory that produces dependencies using an asynchronous, non-throwing resolver.
///
/// `AsyncFactory` is used when dependency creation requires `await`. The `Dependency`
/// type must conform to `Sendable`. When injected via the ``Injected(_:)-4jgny`` macro,
/// the wrapped value type is `Task<Dependency, Never>`.
///
/// ```swift
/// extension Container {
///     static let session = Factory { await URLSession.shared }
/// }
///
/// // Direct resolution
/// let session = await Container.session()
/// ```
///
/// With cached or shared scope, concurrent resolutions are deduplicated -- only one
/// async task runs the resolver, and all concurrent callers await the same result.
public final class AsyncFactory<Dependency: Sendable>: _Factory, @unchecked Sendable {
    /// The closure signature used to create the dependency.
    public typealias Resolver = @Sendable () async -> Dependency
    /// The scope that controls instance lifetime for this factory.
    public let scope: Scope
    let resolver: Resolver
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }

    /// Resolves and returns the dependency asynchronously.
    ///
    /// - Returns: The resolved dependency.
    public func callAsFunction(file: String = #file, line: UInt = #line, function: String = #function) async -> Dependency {
        await Container.current.resolve(factory: self, file: file, line: line, function: function)
    }

    /// Pushes a new resolver onto the current container's registration stack.
    ///
    /// Clears cached values if this factory uses a cached or shared scope.
    ///
    /// - Parameter resolver: The closure that creates the dependency.
    public func register(_ resolver: @escaping Resolver) {
        (scope as? ScopeWithCache)?.cache.clear()
        Container.current.addResolver(for: self, resolver: resolver)
    }

    /// Removes the most recent resolver override from the current container's registration stack.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }

    /// Marks this factory to bypass test overrides and always use its default production resolver.
    ///
    /// > Warning: This sets a global flag that persists across concurrent tests and can cause
    /// > test interference. Prefer using ``register(_:)`` with explicit test doubles instead.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func useProduction() -> Self {
        Container.current.useProduction(on: self)
        return self
    }
}

/// A factory that produces dependencies using an asynchronous, throwing resolver.
///
/// `AsyncThrowingFactory` is the most flexible factory type -- its resolver can both
/// `await` and `throw`. The `Dependency` type must conform to `Sendable`. When injected
/// via the ``Injected(_:)-4jgny`` macro, the wrapped value type is `Task<Dependency, any Error>`.
///
/// ```swift
/// extension Container {
///     static let database = Factory { try await Database.connect() }
/// }
///
/// // Direct resolution
/// let db = try await Container.database()
/// ```
public final class AsyncThrowingFactory<Dependency: Sendable>: _Factory, @unchecked Sendable {
    /// The closure signature used to create the dependency.
    public typealias Resolver = @Sendable () async throws -> Dependency

    /// The scope that controls instance lifetime for this factory.
    public let scope: Scope
    let resolver: Resolver
    init(scope: Scope, resolver: @escaping Resolver) {
        self.scope = scope
        self.resolver = resolver
        Container.default.register(factory: self)
    }

    /// Resolves and returns the dependency asynchronously, or throws if the resolver fails.
    ///
    /// - Returns: The resolved dependency.
    /// - Throws: Any error thrown by the active resolver.
    public func callAsFunction(file: String = #file, line: UInt = #line, function: String = #function) async throws -> Dependency {
        try await Container.current.resolve(factory: self, file: file, line: line, function: function)
    }

    /// Pushes a new resolver onto the current container's registration stack.
    ///
    /// Clears cached values if this factory uses a cached or shared scope.
    ///
    /// - Parameter resolver: The closure that creates the dependency.
    public func register(_ resolver: @escaping Resolver) {
        (scope as? ScopeWithCache)?.cache.clear()
        Container.current.addResolver(for: self, resolver: resolver)
    }

    /// Removes the most recent resolver override from the current container's registration stack.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func popRegistration() -> Self {
        Container.current.popResolver(for: self)
        return self
    }

    /// Marks this factory to bypass test overrides and always use its default production resolver.
    ///
    /// > Warning: This sets a global flag that persists across concurrent tests and can cause
    /// > test interference. Prefer using ``register(_:)`` with explicit test doubles instead.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult public func useProduction() -> Self {
        Container.current.useProduction(on: self)
        return self
    }
}

/// Creates a synchronous, non-throwing factory.
///
/// This is the primary way to define dependencies. Store the result as a static property
/// on ``Container``:
///
/// ```swift
/// extension Container {
///     static let logger = Factory { ConsoleLogger() as Logger }
///     static let analytics = Factory(scope: .cached) { AnalyticsService() }
/// }
/// ```
///
/// The closure is used as the default production resolver. It can be overridden per-container
/// using ``SyncFactory/register(_:)``.
///
/// - Parameters:
///   - scope: The lifetime strategy for resolved instances. Defaults to ``Scope/unique``.
///   - resolver: A closure that creates the dependency.
/// - Returns: A ``SyncFactory`` for the dependency type.
public func Factory<Dependency>(scope: Scope = .unique, resolver: @escaping () -> Dependency) -> SyncFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}

/// Creates a synchronous, throwing factory.
///
/// Use this when dependency creation can fail:
///
/// ```swift
/// extension Container {
///     static let config = Factory { try loadConfig() }
/// }
/// ```
///
/// - Parameters:
///   - scope: The lifetime strategy for resolved instances. Defaults to ``Scope/unique``.
///   - resolver: A closure that creates the dependency or throws.
/// - Returns: A ``SyncThrowingFactory`` for the dependency type.
public func Factory<Dependency>(scope: Scope = .unique, resolver: @escaping () throws -> Dependency) -> SyncThrowingFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}

/// Creates an asynchronous, non-throwing factory.
///
/// Use this when dependency creation requires `await`:
///
/// ```swift
/// extension Container {
///     static let session = Factory { await URLSession.shared }
/// }
/// ```
///
/// - Parameters:
///   - scope: The lifetime strategy for resolved instances. Defaults to ``Scope/unique``.
///   - resolver: A `Sendable` closure that asynchronously creates the dependency.
/// - Returns: An ``AsyncFactory`` for the dependency type.
public func Factory<Dependency>(scope: Scope = .unique, resolver: @Sendable @escaping () async -> Dependency) -> AsyncFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}

/// Creates an asynchronous, throwing factory.
///
/// Use this when dependency creation requires both `await` and `throws`:
///
/// ```swift
/// extension Container {
///     static let database = Factory { try await Database.connect() }
/// }
/// ```
///
/// - Parameters:
///   - scope: The lifetime strategy for resolved instances. Defaults to ``Scope/unique``.
///   - resolver: A `Sendable` closure that asynchronously creates the dependency or throws.
/// - Returns: An ``AsyncThrowingFactory`` for the dependency type.
public func Factory<Dependency>(scope: Scope = .unique, resolver: @Sendable @escaping () async throws -> Dependency) -> AsyncThrowingFactory<Dependency> {
    .init(scope: scope, resolver: resolver)
}
