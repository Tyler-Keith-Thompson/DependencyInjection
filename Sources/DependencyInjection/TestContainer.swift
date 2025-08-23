//
//  TestContainer.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//
import Foundation
import ServiceContextModule
import DispatchInterpose
import Atomics

final class TestContainer: Container, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let unregisteredBehavior: UnregisteredBehavior
    let leakedResolutionBehavior: any LeakedResolutionBehavior
    let _parent: Container
    private var storage = [AnyHashable: StorageBase]()

    private var _executingTest = ManagedAtomic(false)
    var executingTest: Bool {
        get { _executingTest.load(ordering: .sequentiallyConsistent) }
        set { _executingTest.store(newValue, ordering: .sequentiallyConsistent) }
    }
    
    init(parent: Container, unregisteredBehavior: UnregisteredBehavior, leakedResolutionBehavior: any LeakedResolutionBehavior) {
        self.unregisteredBehavior = unregisteredBehavior
        self.leakedResolutionBehavior = leakedResolutionBehavior
        self._parent = parent
        super.init(parent: parent)
    }
    
    override func resolve<D>(factory: SyncFactory<D>) -> D {
        if storage(for: factory).syncRegistrations.currentResolver() != nil {
            #if DEBUG
            guard executingTest else {
                return leakedResolutionBehavior.resolve(factory: factory)
            }
            #endif
            unregisteredBehavior.trigger(factory: factory, dependency: D.self)
        }
        return _parent.resolve(factory: factory)
    }
    
    override func resolve<D>(factory: SyncThrowingFactory<D>) throws -> D {
        if storage(for: factory).syncThrowingRegistrations.currentResolver() != nil {
            #if DEBUG
            guard executingTest else {
                return try leakedResolutionBehavior.resolve(factory: factory)
            }
            #endif
            unregisteredBehavior.trigger(factory: factory, dependency: D.self)
        }
        return try _parent.resolve(factory: factory)
    }

    override func resolve<D>(factory: AsyncFactory<D>) async -> D {
        if storage(for: factory).asyncRegistrations.currentResolver() != nil {
            #if DEBUG
            guard executingTest else {
                return await leakedResolutionBehavior.resolve(factory: factory)
            }
            #endif
            unregisteredBehavior.trigger(factory: factory, dependency: D.self)
        }
        return await _parent.resolve(factory: factory)
    }

    override func resolve<D>(factory: AsyncThrowingFactory<D>) async throws -> D {
        if storage(for: factory).asyncThrowingRegistrations.currentResolver() != nil {
            #if DEBUG
            guard executingTest else {
                return try await leakedResolutionBehavior.resolve(factory: factory)
            }
            #endif
            unregisteredBehavior.trigger(factory: factory, dependency: D.self)
        }
        return try await _parent.resolve(factory: factory)
    }
    
    override func addResolver<D>(for factory: SyncFactory<D>, resolver: @escaping SyncFactory<D>.Resolver) {
        storage(for: factory).syncRegistrations.clear()
        return _parent.addResolver(for: factory, resolver: resolver)
    }
    
    override func addResolver<D>(for factory: SyncThrowingFactory<D>, resolver: @escaping SyncThrowingFactory<D>.Resolver) {
        storage(for: factory).syncThrowingRegistrations.clear()
        return _parent.addResolver(for: factory, resolver: resolver)
    }
    
    override func addResolver<D>(for factory: AsyncFactory<D>, resolver: @escaping AsyncFactory<D>.Resolver) {
        storage(for: factory).asyncRegistrations.clear()
        return _parent.addResolver(for: factory, resolver: resolver)
    }
    
    override func addResolver<D>(for factory: AsyncThrowingFactory<D>, resolver: @escaping AsyncThrowingFactory<D>.Resolver) {
        storage(for: factory).asyncThrowingRegistrations.clear()
        return _parent.addResolver(for: factory, resolver: resolver)
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

public enum LeakedResolutionStrategy<D> {
    case returnValue(D)
    case useProductionValue
}
public protocol LeakedResolutionBehavior {
    func onLeak<D>(factory: SyncFactory<D>) -> LeakedResolutionStrategy<D>
    func onLeak<D>(factory: SyncThrowingFactory<D>) throws -> LeakedResolutionStrategy<D>
    func onLeak<D>(factory: AsyncFactory<D>) async -> LeakedResolutionStrategy<D>
    func onLeak<D>(factory: AsyncThrowingFactory<D>) async throws -> LeakedResolutionStrategy<D>
}

extension LeakedResolutionBehavior {
    func resolve<D>(factory: SyncFactory<D>) -> D {
        // TODO: Log leak
        switch onLeak(factory: factory) {
        case .returnValue(let value): return value
        case .useProductionValue: return factory.resolver()
        }
    }
    
    func resolve<D>(factory: SyncThrowingFactory<D>) throws -> D {
        // TODO: Log leak
        switch try onLeak(factory: factory) {
        case .returnValue(let value): return value
        case .useProductionValue: return try factory.resolver()
        }
    }
    
    func resolve<D>(factory: AsyncFactory<D>) async -> D {
        // TODO: Log leak
        switch await onLeak(factory: factory) {
        case .returnValue(let value): return value
        case .useProductionValue: return await factory.resolver()
        }
    }
    
    func resolve<D>(factory: AsyncThrowingFactory<D>) async throws -> D {
        // TODO: Log leak
        switch try await onLeak(factory: factory) {
        case .returnValue(let value): return value
        case .useProductionValue: return try await factory.resolver()
        }
    }
}

enum ResolutionError: Error {
    case leakedResolution
}

public struct DefaultLeakedResolutionBehavior: LeakedResolutionBehavior {
    public init() { }
    
    public func onLeak<D>(factory: SyncFactory<D>) -> LeakedResolutionStrategy<D> {
        // environment variable DO_BEST_EFFORT_RESOLUTION=true
        // crashy crashy
        // First step, let's cancel the current task (if any, they might've used GCD)
        // Theoretically this should stop many possible bad things happening (like network requests)
        withUnsafeCurrentTask { $0?.cancel() }        

        // if there is one, we can use a supplied test value
        
        // Next, let's see if we can pick some sane default behavior
        // For example, if this returns an optional, can we just return nil?
        if _isOptional(D.self) {
            return .returnValue(Optional<D>.none as! D)
        }
        
        // if all else fails, we canceled the task...just let it use the prod dependency over crashing
        return .useProductionValue
    }
    
    public func onLeak<D>(factory: SyncThrowingFactory<D>) throws -> LeakedResolutionStrategy<D> {
        // First step, let's cancel the current task (if any, they might've used GCD)
        // Theoretically this should stop many possible bad things happening (like network requests)
        withUnsafeCurrentTask { $0?.cancel() }
        throw ResolutionError.leakedResolution
    }
    
    public func onLeak<D>(factory: AsyncFactory<D>) async -> LeakedResolutionStrategy<D> {
        // we know we're executing in a task, let's just suspend indefinitely
        await withUnsafeContinuation { (_: UnsafeContinuation<Never, Never>) in
            // never resume
        }
    }
    
    public func onLeak<D>(factory: AsyncThrowingFactory<D>) async throws -> LeakedResolutionStrategy<D> {
        // we know we're executing in a task, let's just suspend indefinitely
        await withUnsafeContinuation { (_: UnsafeContinuation<Never, Never>) in
            // never resume
        }
    }
}

//public enum LeakedResolutionBehavior {
//    case readFromEnvironment // default
//    case bestEffortResolveSomething
//    case crash
//    case crashIfNoTestValue
//    case custom(@Sendable (String) -> Void)
//}

public enum UnregisteredBehavior {
    case fatalError
    @available(*, deprecated, message: "Warning! Using a custom action will still resolve production dependencies unless you manually stop code execution.")
    case custom(@Sendable (String) -> Void)
    
    func trigger<T, D>(factory: T, dependency: D.Type) {
        switch self {
        case .fatalError:
            Swift.fatalError("Dependency: \(dependency) on factory: \(factory) not registered!")
        case .custom(let action):
            action("\(factory)")
        }
    }
}

@discardableResult
public func withTestContainer<T>(unregisteredBehavior: UnregisteredBehavior = .fatalError,
                                 leakedResolutionBehavior: any LeakedResolutionBehavior = DefaultLeakedResolutionBehavior(),
                                 operation: () throws -> T) rethrows -> T {
    swift_async_hooks_install()
    var context = ServiceContext.inUse
    let originalFatalErrorOnResolveValue = Container.default.fatalErrorOnResolve
    Container.default.fatalErrorOnResolve = true
    defer {
        Container.default.fatalErrorOnResolve = originalFatalErrorOnResolveValue
    }
    let testContainer = TestContainer(parent: Container(parent: Container.current),
                                      unregisteredBehavior: unregisteredBehavior,
                                      leakedResolutionBehavior: leakedResolutionBehavior)
    context.container = testContainer
    return try ServiceContext.withValue(context, operation: {
        testContainer.executingTest = true
        defer { testContainer.executingTest = false }
        return try operation()
    })
}

@discardableResult
public func withTestContainer<T>(isolation: isolated(any Actor)? = #isolation,
                                 unregisteredBehavior: UnregisteredBehavior = .fatalError,
                                 leakedResolutionBehavior: any LeakedResolutionBehavior = DefaultLeakedResolutionBehavior(),
                                 operation: () async throws -> T) async rethrows -> T {
    swift_async_hooks_install()
    var context = ServiceContext.inUse
    let originalFatalErrorOnResolveValue = Container.default.fatalErrorOnResolve
    Container.default.fatalErrorOnResolve = true
    defer {
        Container.default.fatalErrorOnResolve = originalFatalErrorOnResolveValue
    }
    let testContainer = TestContainer(parent: Container(parent: Container.current),
                                      unregisteredBehavior: unregisteredBehavior,
                                      leakedResolutionBehavior: leakedResolutionBehavior)
    context.container = testContainer
    return try await ServiceContext.withValue(context, operation: {
        testContainer.executingTest = true
        defer { testContainer.executingTest = false }
        return try await operation()
    })
}
