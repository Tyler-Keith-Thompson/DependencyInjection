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
        if storage(for: factory).syncRegistrations.currentResolver() != nil {
            switch unregisteredBehavior {
            case .fatalError:
                fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
            case .custom(let action):
                action("\(factory)")
            }
        }
        return _parent.resolve(factory: factory)
    }
    
    override func resolve<D>(factory: SyncThrowingFactory<D>) throws -> D {
        if storage(for: factory).syncThrowingRegistrations.currentResolver() != nil {
            switch unregisteredBehavior {
            case .fatalError:
                fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
            case .custom(let action):
                action("\(factory)")
            }
        }
        return try _parent.resolve(factory: factory)
    }

    override func resolve<D>(factory: AsyncFactory<D>) async -> D {
        if storage(for: factory).asyncRegistrations.currentResolver() != nil {
            switch unregisteredBehavior {
            case .fatalError:
                fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
            case .custom(let action):
                action("\(factory)")
            }
        }
        return await _parent.resolve(factory: factory)
    }

    override func resolve<D>(factory: AsyncThrowingFactory<D>) async throws -> D {
        if storage(for: factory).asyncThrowingRegistrations.currentResolver() != nil {
            switch unregisteredBehavior {
            case .fatalError:
                fatalError("Dependency: \(D.self) on factory: \(factory) not registered!")
            case .custom(let action):
                action("\(factory)")
            }
        }
        return try await _parent.resolve(factory: factory)
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
            storage.syncRegistrations.add { fatalError() }
            storage.syncThrowingRegistrations.add { fatalError() }
            storage.asyncRegistrations.add { fatalError() }
            storage.asyncThrowingRegistrations.add { fatalError() }
        }
    }
}

public enum UnregisteredBehavior {
    case fatalError
    @available(*, deprecated, message: "Warning! Using a custom action will still resolve production dependencies unless you manually stop code execution.")
    case custom(@Sendable (String) -> Void)
}

public func withTestContainer<T>(unregisteredBehavior: UnregisteredBehavior = .fatalError, operation: () throws -> T) rethrows -> T {
    var context = ServiceContext.topLevel
    context.container = TestContainer(parent: Container.current, unregisteredBehavior: unregisteredBehavior)
    return try ServiceContext.withValue(context, operation: operation)
}

//@available(*, deprecated, message: "Prefer withNestedContainer(isolation:operation:)")
@_disfavoredOverload
@_unsafeInheritExecutor // Deprecated trick to avoid executor hop here; 6.0 introduces the proper replacement: #isolation
public func withTestContainer<T>(unregisteredBehavior: UnregisteredBehavior = .fatalError, operation: () async throws -> T) async rethrows -> T {
    var context = ServiceContext.topLevel
    context.container = TestContainer(parent: Container.current, unregisteredBehavior: unregisteredBehavior)
    return try await ServiceContext.withValue(context, operation: operation)
}