//
//  Container.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/31/24.
//
import Foundation

public class Container: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var storage = [AnyHashable: StorageBase]()
    
    var parent: Container?
    init(parent: Container? = nil) {
        self.parent = parent
    }
    
    private func __lockedStorage<F: _Factory>(for factory: F) -> Storage<F>? {
        lock.lock()
        defer { lock.unlock() }
        return (self.storage[factory] as? Storage<F>) ?? parent?.__lockedStorage(for: factory)
    }
    
    private func _storage<F: _Factory>(for factory: F) -> Storage<F> {
        ((self.storage[factory] as? Storage<F>) ?? parent?.__lockedStorage(for: factory))!
    }
    
    func storage<F: _Factory>(for factory: F) -> Storage<F> {
        lock.lock()
        defer { lock.unlock() }
        return _storage(for: factory)
    }
    
    func resolve<D>(factory: SyncFactory<D>) -> D {
        let currentRegisteredResolver = storage(for: factory).syncRegistrations.currentResolver() ?? parent?.__lockedStorage(for: factory)?.syncRegistrations.currentResolver()
        let currentResolver = currentRegisteredResolver ?? factory.resolver
        return factory.scope.resolve(resolver: currentResolver)
    }
    
    func resolve<D>(factory: SyncThrowingFactory<D>) throws -> D {
        let currentRegisteredResolver = storage(for: factory).syncThrowingRegistrations.currentResolver() ?? parent?.__lockedStorage(for: factory)?.syncThrowingRegistrations.currentResolver()
        let currentResolver = currentRegisteredResolver ?? factory.resolver
        return try factory.scope.resolve(resolver: currentResolver)
    }

    func resolve<D>(factory: AsyncFactory<D>) async -> D {
        let currentRegisteredResolver = storage(for: factory).asyncRegistrations.currentResolver() ?? parent?.__lockedStorage(for: factory)?.asyncRegistrations.currentResolver()
        let currentResolver = currentRegisteredResolver ?? factory.resolver
        return await factory.scope.resolve(resolver: currentResolver)
    }

    func resolve<D>(factory: AsyncThrowingFactory<D>) async throws -> D {
        let currentRegisteredResolver = storage(for: factory).asyncThrowingRegistrations.currentResolver() ?? parent?.__lockedStorage(for: factory)?.asyncThrowingRegistrations.currentResolver()
        let currentResolver = currentRegisteredResolver ?? factory.resolver
        return try await factory.scope.resolve(resolver: currentResolver)
    }
    
    func addResolver<D>(for factory: SyncFactory<D>, resolver: @escaping SyncFactory<D>.Resolver) {
        register(factory: factory)
        storage(for: factory).syncRegistrations.add(resolver: resolver)
    }
    
    func addResolver<D>(for factory: SyncThrowingFactory<D>, resolver: @escaping SyncThrowingFactory<D>.Resolver) {
        register(factory: factory)
        storage(for: factory).syncThrowingRegistrations.add(resolver: resolver)
    }
    
    func addResolver<D>(for factory: AsyncFactory<D>, resolver: @escaping AsyncFactory<D>.Resolver) {
        register(factory: factory)
        storage(for: factory).asyncRegistrations.add(resolver: resolver)
    }
    
    func addResolver<D>(for factory: AsyncThrowingFactory<D>, resolver: @escaping AsyncThrowingFactory<D>.Resolver) {
        register(factory: factory)
        storage(for: factory).asyncThrowingRegistrations.add(resolver: resolver)
    }
    
    func popResolver(for factory: some _Factory) {
        register(factory: factory)
        let storage = storage(for: factory)
        storage.syncRegistrations.pop()
        storage.syncThrowingRegistrations.pop()
        storage.asyncRegistrations.pop()
        storage.asyncThrowingRegistrations.pop()
    }
    
    func register(factory: some _Factory) {
        lock.lock()
        defer { lock.unlock() }
        if storage[factory] == nil {
            storage[factory] = Storage(factory: factory)
        }
    }
}

extension Container {
    class StorageBase { }
    
    final class Storage<Factory: _Factory>: StorageBase, @unchecked Sendable {
        private let lock = NSRecursiveLock()
        let syncRegistrations = SyncRegistrations<Factory.Dependency>()
        let syncThrowingRegistrations = SyncThrowingRegistrations<Factory.Dependency>()
        let asyncRegistrations = AsyncRegistrations<Factory.Dependency>()
        let asyncThrowingRegistrations = AsyncThrowingRegistrations<Factory.Dependency>()
        
        init(factory: Factory) { }
    }
}
