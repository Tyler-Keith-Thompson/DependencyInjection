//
//  TestContainer.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//
import Foundation
import ServiceContextModule

final class TestContainer: Container, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let unregisteredBehavior: UnregisteredBehavior
    let _parent: Container
    private var storage = [AnyHashable: StorageBase]()
    
    init(parent: Container, unregisteredBehavior: UnregisteredBehavior) {
        self.unregisteredBehavior = unregisteredBehavior
        self._parent = parent
        super.init(parent: parent)
    }
    
    override func resolve<D>(factory: SyncFactory<D>) -> D {
        if let registered = storage(for: factory).syncRegistrations.currentResolver() {
            return factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
        case .custom(let action):
            action("\(factory)")
        }
        return factory.resolver()
    }
    
    override func resolve<D>(factory: SyncThrowingFactory<D>) throws -> D {
        if let registered = storage(for: factory).syncThrowingRegistrations.currentResolver() {
            return try factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
        case .custom(let action):
            action("\(factory)")
        }
        return try factory.resolver()
    }

    override func resolve<D>(factory: AsyncFactory<D>) async -> D {
        if let registered = storage(for: factory).asyncRegistrations.currentResolver() {
            return await factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
        case .custom(let action):
            action("\(factory)")
        }
        return await factory.resolver()
    }

    override func resolve<D>(factory: AsyncThrowingFactory<D>) async throws -> D {
        if let registered = storage(for: factory).asyncThrowingRegistrations.currentResolver() {
            return try await factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
        case .custom(let action):
            action("\(factory)")
        }
        return try await factory.resolver()
    }
    
    override func addResolver<D>(for factory: SyncFactory<D>, resolver: @escaping SyncFactory<D>.Resolver) {
        storage(for: factory).syncRegistrations.add(resolver: resolver)
    }
    
    override func addResolver<D>(for factory: SyncThrowingFactory<D>, resolver: @escaping SyncThrowingFactory<D>.Resolver) {
        storage(for: factory).syncThrowingRegistrations.add(resolver: resolver)
    }
    
    override func addResolver<D>(for factory: AsyncFactory<D>, resolver: @escaping AsyncFactory<D>.Resolver) {
        storage(for: factory).asyncRegistrations.add(resolver: resolver)
    }
    
    override func addResolver<D>(for factory: AsyncThrowingFactory<D>, resolver: @escaping AsyncThrowingFactory<D>.Resolver) {
        storage(for: factory).asyncThrowingRegistrations.add(resolver: resolver)
    }

    override func storage<F: _Factory>(for factory: F) -> Storage<F> {
        register(factory: factory)
        return storage[factory]! as! Container.Storage<F>
    }
    
    override func register<F: _Factory>(factory: F) {
        lock.lock()
        defer { lock.unlock() }
        if storage[factory] == nil {
            let storage = Storage(factory: factory)
            self.storage[factory] = storage
        }
    }
}

public enum UnregisteredBehavior {
    case fatalError
    @available(*, deprecated, message: "Warning! Using a custom action will still resolve production dependencies unless you manually stop code execution.")
    case custom(@Sendable (String) -> Void)
}

public func withTestContainer<T>(unregisteredBehavior: UnregisteredBehavior = .fatalError, operation: () throws -> T) rethrows -> T {
    var context = ServiceContext.inUse
    let previous = Container.default.fatalErrorOnResolve
    Container.default.fatalErrorOnResolve = true
    defer { Container.default.fatalErrorOnResolve = previous }
    context.container = TestContainer(parent: Container(parent: Container.current), unregisteredBehavior: unregisteredBehavior)
    return try ServiceContext.withValue(context, operation: operation)
}

public func withTestContainer<T>(isolation: isolated(any Actor)? = #isolation, unregisteredBehavior: UnregisteredBehavior = .fatalError, operation: () async throws -> T) async rethrows -> T {
    var context = ServiceContext.inUse
    let previous = Container.default.fatalErrorOnResolve
    Container.default.fatalErrorOnResolve = true
    defer { Container.default.fatalErrorOnResolve = previous }
    context.container = TestContainer(parent: Container(parent: Container.current), unregisteredBehavior: unregisteredBehavior)
    return try await ServiceContext.withValue(context, operation: operation)
}
