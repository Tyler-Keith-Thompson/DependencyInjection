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

// File-level atomics for concurrent withTestContainer race condition protection
private let _fatalErrorOnResolveRefCount = ManagedAtomic<Int>(0)
private nonisolated(unsafe) var _originalFatalErrorOnResolveValue: Bool = false
private let _fatalErrorOnResolveValueSaved = ManagedAtomic<Bool>(false)

// Special container that cannot store any registrations - used as parent for TestContainer
private final class IsolatedContainer: Container {
    override func addResolver<D>(for factory: SyncFactory<D>, resolver: @escaping SyncFactory<D>.Resolver) {
        // Do nothing - prevent any registrations
    }
    
    override func addResolver<D>(for factory: SyncThrowingFactory<D>, resolver: @escaping SyncThrowingFactory<D>.Resolver) {
        // Do nothing - prevent any registrations
    }
    
    override func addResolver<D>(for factory: AsyncFactory<D>, resolver: @escaping AsyncFactory<D>.Resolver) {
        // Do nothing - prevent any registrations
    }
    
    override func addResolver<D>(for factory: AsyncThrowingFactory<D>, resolver: @escaping AsyncThrowingFactory<D>.Resolver) {
        // Do nothing - prevent any registrations
    }
    
    override func storage<F: _Factory>(for factory: F) -> Storage<F>? {
        // Return nil - no storage available
        return nil
    }
}

final class TestContainer: Container, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let unregisteredBehavior: UnregisteredBehavior
    let leakedResolutionBehavior: any LeakedResolutionBehavior
    let _parent: Container
    private var storage = [AnyHashable: StorageBase]()
    let testContainerFile: String
    let testContainerLine: UInt
    let testContainerFunction: String

    private var _executingTest = ManagedAtomic(false)
    var executingTest: Bool {
        get { _executingTest.load(ordering: .sequentiallyConsistent) }
        set { _executingTest.store(newValue, ordering: .sequentiallyConsistent) }
    }
    
    init(parent: Container, unregisteredBehavior: UnregisteredBehavior, leakedResolutionBehavior: any LeakedResolutionBehavior, file: String = #file, line: UInt = #line, function: String = #function) {
        self.unregisteredBehavior = unregisteredBehavior
        self.leakedResolutionBehavior = leakedResolutionBehavior
        self._parent = parent
        self.testContainerFile = file
        self.testContainerLine = line
        self.testContainerFunction = function
        super.init(parent: parent)
    }
    
    override func resolve<D>(factory: SyncFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) -> D {
        if let registered = storage(for: factory)?.syncRegistrations.currentResolver() {
            return factory.scope.resolve(resolver: registered)
        }
        
        #if DEBUG
        guard executingTest else {
            return leakedResolutionBehavior.resolve(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
        }
        #endif
        
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return factory.resolver()
    }
    
    override func resolve<D>(factory: SyncThrowingFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) throws -> D {
        if let registered = storage(for: factory)?.syncThrowingRegistrations.currentResolver() {
            return try factory.scope.resolve(resolver: registered)
        }
        
        #if DEBUG
        guard executingTest else {
            return try leakedResolutionBehavior.resolve(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
        }
        #endif
        
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return try factory.resolver()
    }

    override func resolve<D>(factory: AsyncFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) async -> D {
        if let registered = storage(for: factory)?.asyncRegistrations.currentResolver() {
            return await factory.scope.resolve(resolver: registered)
        }
        
        #if DEBUG
        guard executingTest else {
            return await leakedResolutionBehavior.resolve(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
        }
        #endif
        
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return await factory.resolver()
    }

    override func resolve<D>(factory: AsyncThrowingFactory<D>, hasTaskLocalContext: Bool = false, file: String = #file, line: UInt = #line, function: String = #function) async throws -> D {
        if let registered = storage(for: factory)?.asyncThrowingRegistrations.currentResolver() {
            return try await factory.scope.resolve(resolver: registered)
        }
        
        #if DEBUG
        guard executingTest else {
            return try await leakedResolutionBehavior.resolve(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
        }
        #endif
        
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return try await factory.resolver()
    }
    
    override func addResolver<D>(for factory: SyncFactory<D>, resolver: @escaping SyncFactory<D>.Resolver) {
        storage(for: factory)?.syncRegistrations.add(resolver: resolver)
    }
    
    override func addResolver<D>(for factory: SyncThrowingFactory<D>, resolver: @escaping SyncThrowingFactory<D>.Resolver) {
        storage(for: factory)?.syncThrowingRegistrations.add(resolver: resolver)
    }
    
    override func addResolver<D>(for factory: AsyncFactory<D>, resolver: @escaping AsyncFactory<D>.Resolver) {
        storage(for: factory)?.asyncRegistrations.add(resolver: resolver)
    }
    
    override func addResolver<D>(for factory: AsyncThrowingFactory<D>, resolver: @escaping AsyncThrowingFactory<D>.Resolver) {
        storage(for: factory)?.asyncThrowingRegistrations.add(resolver: resolver)
    }

    override func storage<F: _Factory>(for factory: F) -> Storage<F>? {
        lock.protect {
            if let storage = storage[factory] as? Container.Storage<F> {
                return storage
            } else {
                let newStorage = Container.Storage(factory: factory)
                storage[factory] = newStorage
                return newStorage
            }
        }
    }
}

public enum LeakedResolutionStrategy<D> {
    case returnValue(D)
    case useProductionValue
}
public protocol LeakedResolutionBehavior {
    func onLeak<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> LeakedResolutionStrategy<D>
    func onLeak<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> LeakedResolutionStrategy<D>
    func onLeak<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> LeakedResolutionStrategy<D>
    func onLeak<D>(factory: AsyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async throws -> LeakedResolutionStrategy<D>
}

extension LeakedResolutionBehavior {
    func resolve<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> D {
        switch onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction) {
        case .returnValue(let value): return value
        case .useProductionValue: return factory.resolver()
        }
    }
    
    func resolve<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> D {
        switch try onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction) {
        case .returnValue(let value): return value
        case .useProductionValue: return try factory.resolver()
        }
    }
    
    func resolve<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> D {
        switch await onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction) {
        case .returnValue(let value): return value
        case .useProductionValue: return await factory.resolver()
        }
    }
    
    func resolve<D>(factory: AsyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async throws -> D {
        switch try await onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction) {
        case .returnValue(let value): return value
        case .useProductionValue: return try await factory.resolver()
        }
    }
}

enum ResolutionError: Error {
    case leakedResolution
}

public struct BestEffortLeakedResolutionBehavior: LeakedResolutionBehavior {
    public init() { }
    
    public func onLeak<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> LeakedResolutionStrategy<D> {
        // environment variable DO_BEST_EFFORT_RESOLUTION=true
        // crashy crashy
        // First step, let's cancel the current task (if any, they might've used GCD)
        // Theoretically this should stop many possible bad things happening (like network requests)
        withUnsafeCurrentTask { $0?.cancel() }
        
        print("⚠️ DEPENDENCY LEAK DETECTED: Factory \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")

        // if there is one, we can use a supplied test value
        
        // Next, let's see if we can pick some sane default behavior
        // For example, if this returns an optional, can we just return nil?
        if _isOptional(D.self) {
            return .returnValue(Optional<D>.none as! D)
        }
        
        // if all else fails, we canceled the task...just let it use the prod dependency over crashing
        return .useProductionValue
    }
    
    public func onLeak<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> LeakedResolutionStrategy<D> {
        // First step, let's cancel the current task (if any, they might've used GCD)
        // Theoretically this should stop many possible bad things happening (like network requests)
        withUnsafeCurrentTask { $0?.cancel() }
        print("⚠️ DEPENDENCY LEAK DETECTED: Factory \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        throw ResolutionError.leakedResolution
    }
    
    public func onLeak<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> LeakedResolutionStrategy<D> {
        print("⚠️ DEPENDENCY LEAK DETECTED: Factory \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        // cancel then suspend indefinitely to prevent side effects
        withUnsafeCurrentTask { $0?.cancel() }
        await withUnsafeContinuation { (_: UnsafeContinuation<Never, Never>) in
            // never resume
        }
    }
    
    public func onLeak<D>(factory: AsyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async throws -> LeakedResolutionStrategy<D> {
        print("⚠️ DEPENDENCY LEAK DETECTED: Factory \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        // we know we're executing in a task, let's just suspend indefinitely
        await withUnsafeContinuation { (_: UnsafeContinuation<Never, Never>) in
            // never resume
        }
    }
}

public struct CrashLeakedResolutionBehavior: LeakedResolutionBehavior {
    public func onLeak<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> LeakedResolutionStrategy<D> {
        crash(message: "Factory: \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
    }
    
    public func onLeak<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> LeakedResolutionStrategy<D> {
        crash(message: "Factory: \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
    }
    
    public func onLeak<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> LeakedResolutionStrategy<D> {
        crash(message: "Factory: \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
    }
    
    public func onLeak<D>(factory: AsyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async throws -> LeakedResolutionStrategy<D> {
        crash(message: "Factory: \(factory) leaked a resolution. This means that asynchronous code was executed from within `withTestContainer` but was never waited on. Test container was created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
    }
}

public struct DefaultLeakedResolutionBehavior: LeakedResolutionBehavior {
    let chosenBehavior: any LeakedResolutionBehavior
    public init() {
        chosenBehavior = ProcessInfo.processInfo.environment["DI_BEST_EFFORT_LEAK_RESOLUTION"] == "true" ? BestEffortLeakedResolutionBehavior() : CrashLeakedResolutionBehavior()
    }
    
    public func onLeak<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> LeakedResolutionStrategy<D> {
        chosenBehavior.onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
    }
    
    public func onLeak<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> LeakedResolutionStrategy<D> {
        try chosenBehavior.onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
    }
    
    public func onLeak<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> LeakedResolutionStrategy<D> {
        await chosenBehavior.onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
    }
    
    public func onLeak<D>(factory: AsyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async throws -> LeakedResolutionStrategy<D> {
        try await chosenBehavior.onLeak(factory: factory, testContainerFile: testContainerFile, testContainerLine: testContainerLine, testContainerFunction: testContainerFunction)
    }
}

func crash(message: String) -> Never {
    #if _runtime(_ObjC)
        NSException(name: .internalInconsistencyException, reason: message, userInfo: nil).raise()
    #endif
    Swift.fatalError(message)
}

public enum UnregisteredBehavior {
    case fatalError
    @available(*, deprecated, message: "Warning! Using a custom action will still resolve production dependencies unless you manually stop code execution.")
    case custom(@Sendable (String) -> Void)
    
    func trigger<T, D>(factory: T, dependency: D.Type) {
        switch self {
        case .fatalError:
            crash(message: "Dependency: \(dependency) on factory: \(factory) not registered!")
        case .custom(let action):
            action("\(factory)")
        }
    }
}

// Main functions with both leak detection and traceability
@discardableResult
public func withTestContainer<T>(unregisteredBehavior: UnregisteredBehavior = .fatalError,
                                 leakedResolutionBehavior: any LeakedResolutionBehavior = DefaultLeakedResolutionBehavior(),
                                 file: String = #file, line: UInt = #line, function: String = #function,
                                 operation: () throws -> T) rethrows -> T {
    swift_async_hooks_install()
    var context = ServiceContext.inUse
    
    // Atomic reference counting solution to fix race condition
    let refCount = _fatalErrorOnResolveRefCount.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
    if refCount == 1 {
        // First entrant - capture and store the original value
        _originalFatalErrorOnResolveValue = Container.default.fatalErrorOnResolve
        _fatalErrorOnResolveValueSaved.store(true, ordering: .sequentiallyConsistent)
        Container.default.fatalErrorOnResolve = true
    }
    
    defer {
        let refCount = _fatalErrorOnResolveRefCount.wrappingDecrementThenLoad(ordering: .sequentiallyConsistent)
        if refCount == 0 {
            // Last exit - restore the original value and clear saved flag
            Container.default.fatalErrorOnResolve = _originalFatalErrorOnResolveValue
            _fatalErrorOnResolveValueSaved.store(false, ordering: .sequentiallyConsistent)
        }
    }
    
    // Create a parent container that cannot store any registrations for complete isolation
    let isolatedParent = IsolatedContainer(parent: nil)
    let testContainer = TestContainer(parent: isolatedParent,
                                      unregisteredBehavior: unregisteredBehavior,
                                      leakedResolutionBehavior: leakedResolutionBehavior,
                                      file: file, line: line, function: function)
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
                                 file: String = #file, line: UInt = #line, function: String = #function,
                                 operation: () async throws -> T) async rethrows -> T {
    swift_async_hooks_install()
    var context = ServiceContext.inUse
    
    // Atomic reference counting solution to fix race condition
    let refCount = _fatalErrorOnResolveRefCount.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
    if refCount == 1 {
        // First entrant - capture and store the original value
        _originalFatalErrorOnResolveValue = Container.default.fatalErrorOnResolve
        _fatalErrorOnResolveValueSaved.store(true, ordering: .sequentiallyConsistent)
        Container.default.fatalErrorOnResolve = true
    }
    
    defer {
        let refCount = _fatalErrorOnResolveRefCount.wrappingDecrementThenLoad(ordering: .sequentiallyConsistent)
        if refCount == 0 {
            // Last exit - restore the original value and clear saved flag
            Container.default.fatalErrorOnResolve = _originalFatalErrorOnResolveValue
            _fatalErrorOnResolveValueSaved.store(false, ordering: .sequentiallyConsistent)
        }
    }
    
    // Create a parent container that cannot store any registrations for complete isolation
    let isolatedParent = IsolatedContainer(parent: nil)
    let testContainer = TestContainer(parent: isolatedParent,
                                      unregisteredBehavior: unregisteredBehavior,
                                      leakedResolutionBehavior: leakedResolutionBehavior,
                                      file: file, line: line, function: function)
    context.container = testContainer
    return try await ServiceContext.withValue(context, operation: {
        testContainer.executingTest = true
        defer { testContainer.executingTest = false }
        return try await operation()
    })
}
