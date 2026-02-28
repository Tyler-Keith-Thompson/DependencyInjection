//
//  Container.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/31/24.
//
import Foundation
import Atomics

/// The dependency resolution context.
///
/// `Container` holds the registration stacks for all factories and resolves dependencies
/// by walking a parent-child hierarchy. There is always a global ``default`` container,
/// and the framework uses Swift's `ServiceContext` to propagate the ``current`` container
/// through async call chains.
///
/// You typically interact with `Container` in two ways:
///
/// 1. **Define factories** as static properties on `Container`:
///
///    ```swift
///    extension Container {
///        static let logger = Factory { ConsoleLogger() as Logger }
///    }
///    ```
///
/// 2. **Access the current container** for context propagation:
///
///    ```swift
///    let container = Container.current
///    Task.detached {
///        withContainer(container) {
///            // Container.current is restored here
///        }
///    }
///    ```
///
/// Containers form a hierarchy via ``withNestedContainer(operation:)-7glsq``. Child containers
/// inherit registrations from their parent but can override them independently.
public class Container: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var storage = [AnyHashable: StorageBase]()
    private var _fatalErrorOnResolve = ManagedAtomic(false)
    var fatalErrorOnResolve: Bool {
        get { _fatalErrorOnResolve.load(ordering: .sequentiallyConsistent) }
        set { _fatalErrorOnResolve.store(newValue, ordering: .sequentiallyConsistent) }
    }

    var parent: Container?
    init(parent: Container? = nil) {
        self.parent = parent
    }

    func storage<F: _Factory>(for factory: F) -> Storage<F>? {
        lock.protect { (self.storage[factory] as? Storage<F>) }
    }

    func resolve<D>(factory: SyncFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) -> D {
        if fatalErrorOnResolve && !hasTaskLocalContext {
            fatalError("Tried to resolve dependency: \(String(describing: D.self)) when container was set to fatal error on resolution. This is likely because tests executed a task that did not have the container context. This often happens on a detached task. Please use `Container.current` and `withContainer` to add container information back to a detached task. Called from \(file):\(line) in \(function). It's also possible you just didn't use `withTestContainer` around a test that needed it and now have test interference from tests that do use that.")
        }
        if let currentResolver = storage(for: factory)?.syncRegistrations.currentResolver() {
            return factory.scope.resolve(resolver: currentResolver)
        }
        // If no resolver found and parent is a TestContainer, delegate to parent's resolve method
        if let parent = parent {
            return parent.resolve(factory: factory, hasTaskLocalContext: true, file: file, line: line, function: function)
        }
        // Otherwise use the factory's default resolver
        return factory.scope.resolve(resolver: factory.resolver)
    }

    func resolve<D>(factory: SyncThrowingFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) throws -> D {
        if fatalErrorOnResolve && !hasTaskLocalContext {
            fatalError("Tried to resolve dependency: \(String(describing: D.self)) when container was set to fatal error on resolution. This is likely because tests executed a task that did not have the container context. This often happens on a detached task. Please use `Container.current` and `withContainer` to add container information back to a detached task. Called from \(file):\(line) in \(function). It's also possible you just didn't use `withTestContainer` around a test that needed it and now have test interference from tests that do use that.")
        }
        if let currentResolver = storage(for: factory)?.syncThrowingRegistrations.currentResolver() {
            return try factory.scope.resolve(resolver: currentResolver)
        }
        // If no resolver found and parent is a TestContainer, delegate to parent's resolve method
        if let parent = parent {
            return try parent.resolve(factory: factory, hasTaskLocalContext: true, file: file, line: line, function: function)
        }
        // Otherwise use the factory's default resolver
        return try factory.scope.resolve(resolver: factory.resolver)
    }

    func resolve<D>(factory: AsyncFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) async -> D {
        if fatalErrorOnResolve && !hasTaskLocalContext {
            fatalError("Tried to resolve dependency: \(String(describing: D.self)) when container was set to fatal error on resolution. This is likely because tests executed a task that did not have the container context. This often happens on a detached task. Please use `Container.current` and `withContainer` to add container information back to a detached task. Called from \(file):\(line) in \(function). It's also possible you just didn't use `withTestContainer` around a test that needed it and now have test interference from tests that do use that.")
        }
        if let currentResolver = storage(for: factory)?.asyncRegistrations.currentResolver() {
            return await factory.scope.resolve(resolver: currentResolver)
        }
        // If no resolver found and we have a parent, delegate to parent's resolve method
        if let parent = parent {
            return await parent.resolve(factory: factory, hasTaskLocalContext: true, file: file, line: line, function: function)
        }
        // Otherwise use the factory's default resolver
        return await factory.scope.resolve(resolver: factory.resolver)
    }

    func resolve<D>(factory: AsyncThrowingFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) async throws -> D {
        if fatalErrorOnResolve && !hasTaskLocalContext {
            fatalError("Tried to resolve dependency: \(String(describing: D.self)) when container was set to fatal error on resolution. This is likely because tests executed a task that did not have the container context. This often happens on a detached task. Please use `Container.current` and `withContainer` to add container information back to a detached task. Called from \(file):\(line) in \(function). It's also possible you just didn't use `withTestContainer` around a test that needed it and now have test interference from tests that do use that.")
        }
        if let currentResolver = storage(for: factory)?.asyncThrowingRegistrations.currentResolver() {
            return try await factory.scope.resolve(resolver: currentResolver)
        }
        // If no resolver found and we have a parent, delegate to parent's resolve method
        if let parent = parent {
            return try await parent.resolve(factory: factory, hasTaskLocalContext: true, file: file, line: line, function: function)
        }
        // Otherwise use the factory's default resolver
        return try await factory.scope.resolve(resolver: factory.resolver)
    }

    func addResolver<D>(for factory: SyncFactory<D>, resolver: @escaping SyncFactory<D>.Resolver) {
        register(factory: factory).syncRegistrations.add(resolver: resolver)
    }

    func addResolver<D>(for factory: SyncThrowingFactory<D>, resolver: @escaping SyncThrowingFactory<D>.Resolver) {
        register(factory: factory).syncThrowingRegistrations.add(resolver: resolver)
    }

    func addResolver<D>(for factory: AsyncFactory<D>, resolver: @escaping AsyncFactory<D>.Resolver) {
        register(factory: factory).asyncRegistrations.add(resolver: resolver)
    }

    func addResolver<D>(for factory: AsyncThrowingFactory<D>, resolver: @escaping AsyncThrowingFactory<D>.Resolver) {
        register(factory: factory).asyncThrowingRegistrations.add(resolver: resolver)
    }

    func popResolver(for factory: some _Factory) {
        let storage = storage(for: factory)
        storage?.syncRegistrations.pop()
        storage?.syncThrowingRegistrations.pop()
        storage?.asyncRegistrations.pop()
        storage?.asyncThrowingRegistrations.pop()
    }

    @discardableResult func register<F: _Factory>(factory: F) -> Storage<F> {
        lock.protect {
            if let storage = storage[factory] as? Storage<F> {
                return storage
            } else {
                let newStorage = Storage(factory: factory)
                storage[factory] = newStorage
                return newStorage
            }
        }
    }

    func useProduction<F: _Factory>(on factory: F) {
        guard let storage = storage(for: factory) else {
            preconditionFailure("Factory not registered! That should've happened on factory init")
        }
        storage.useProduction = true
    }
}

extension Container {
    class StorageBase { }

    final class Storage<Factory: _Factory>: StorageBase, @unchecked Sendable {
        private let _useProduction = ManagedAtomic(false)
        var useProduction: Bool {
            get { _useProduction.load(ordering: .sequentiallyConsistent) }
            set { _useProduction.store(newValue, ordering: .sequentiallyConsistent) }
        }
        let syncRegistrations = SyncRegistrations<Factory.Dependency>()
        let syncThrowingRegistrations = SyncThrowingRegistrations<Factory.Dependency>()
        let asyncRegistrations = AsyncRegistrations<Factory.Dependency>()
        let asyncThrowingRegistrations = AsyncThrowingRegistrations<Factory.Dependency>()

        init(factory: Factory) { }
    }
}
