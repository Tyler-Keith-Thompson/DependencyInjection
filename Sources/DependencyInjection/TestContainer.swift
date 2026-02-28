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
        let storage = storage(for: factory)
        guard storage?.useProduction != true else { return factory.resolver() }
        if let registered = storage?.syncRegistrations.currentResolver() {
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
        let storage = storage(for: factory)
        guard storage?.useProduction != true else { return try factory.resolver() }
        if let registered = storage?.syncThrowingRegistrations.currentResolver() {
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
        let storage = storage(for: factory)
        guard storage?.useProduction != true else { return await factory.resolver() }
        if let registered = storage?.asyncRegistrations.currentResolver() {
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
        let storage = storage(for: factory)
        guard storage?.useProduction != true else { return try await factory.resolver() }
        if let registered = storage?.asyncThrowingRegistrations.currentResolver() {
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
        register(factory: factory) as? Container.Storage<F>
    }
}

/// The strategy a ``LeakedResolutionBehavior`` returns to handle a leaked resolution.
///
/// - ``returnValue(_:)``: Use a specific fallback value.
/// - ``useProductionValue``: Fall back to the factory's default production resolver.
public enum LeakedResolutionStrategy<D> {
    /// Return the given value instead of resolving the factory.
    case returnValue(D)
    /// Fall back to the factory's default production resolver.
    case useProductionValue
}

/// A protocol for defining how leaked dependency resolutions are handled.
///
/// A "leaked resolution" occurs when async work spawned inside ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)-1hkwu``
/// outlives the test container block and attempts to resolve a dependency after the
/// test container has been torn down.
///
/// Conform to this protocol to implement custom leak handling. Three built-in
/// implementations are provided:
///
/// - ``DefaultLeakedResolutionBehavior``: Checks `DI_BEST_EFFORT_LEAK_RESOLUTION` env var.
/// - ``BestEffortLeakedResolutionBehavior``: Cancels the task and attempts graceful recovery.
/// - ``CrashLeakedResolutionBehavior``: Always crashes with a detailed error.
public protocol LeakedResolutionBehavior {
    /// Called when a sync factory resolution leaks outside the test container scope.
    func onLeak<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> LeakedResolutionStrategy<D>
    /// Called when a sync throwing factory resolution leaks outside the test container scope.
    func onLeak<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> LeakedResolutionStrategy<D>
    /// Called when an async factory resolution leaks outside the test container scope.
    func onLeak<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> LeakedResolutionStrategy<D>
    /// Called when an async throwing factory resolution leaks outside the test container scope.
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

/// A leaked resolution behavior that attempts graceful recovery.
///
/// When a leaked resolution is detected, this behavior:
/// 1. Cancels the current task to stop side effects (e.g., network requests)
/// 2. Returns `nil` for optional dependency types
/// 3. Falls back to the production resolver as a last resort
///
/// For async factories, the task is suspended indefinitely to prevent further execution.
///
/// Use this behavior during development when leaked resolutions are known but not yet fixed:
///
/// ```swift
/// withTestContainer(leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
///     // ...
/// }
/// ```
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

/// A leaked resolution behavior that always crashes with a detailed error message.
///
/// This is the strictest behavior and is the default when the
/// `DI_BEST_EFFORT_LEAK_RESOLUTION` environment variable is not set to `"true"`.
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

/// A leaked resolution behavior that delegates to either ``BestEffortLeakedResolutionBehavior``
/// or ``CrashLeakedResolutionBehavior`` based on the `DI_BEST_EFFORT_LEAK_RESOLUTION` environment variable.
///
/// - If `DI_BEST_EFFORT_LEAK_RESOLUTION=true`, uses ``BestEffortLeakedResolutionBehavior``.
/// - Otherwise, uses ``CrashLeakedResolutionBehavior``.
///
/// This is the default behavior used by ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)-1hkwu``.
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

/// Controls what happens when a dependency is resolved in a test container but has no registered test double.
///
/// By default, ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)-1hkwu``
/// uses ``fatalError``, which crashes immediately with a message identifying both the resolution
/// site and the test container creation site.
public enum UnregisteredBehavior {
    /// Crash immediately with a detailed error identifying the unregistered factory.
    case fatalError
    /// Call a custom handler. The production resolver still runs after the handler returns.
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

/// Executes a synchronous test operation in an isolated container.
///
/// `withTestContainer` creates a child ``Container`` that is completely isolated from the
/// global default and from other concurrent tests. Any factory registrations made inside
/// the block are scoped to this container and automatically cleaned up when the block exits.
///
/// ```swift
/// @Test func myFeatureWorks() {
///     withTestContainer {
///         Container.logger.register { MockLogger() }
///         let service = MyService()
///         service.doWork()
///     }
/// }
/// ```
///
/// **Leak detection:** When async work spawned inside the block outlives it, the
/// ``LeakedResolutionBehavior`` is triggered. By default this crashes; set the
/// `DI_BEST_EFFORT_LEAK_RESOLUTION=true` environment variable for graceful recovery.
///
/// - Parameters:
///   - defaults: Optional ``TestDefaults`` to pre-register in the test container.
///   - unregisteredBehavior: What to do when a factory has no test double. Defaults to ``UnregisteredBehavior/fatalError``.
///   - leakedResolutionBehavior: How to handle resolutions that escape the test scope. Defaults to ``DefaultLeakedResolutionBehavior``.
///   - file: The file where the test container is created (for diagnostics).
///   - line: The line where the test container is created (for diagnostics).
///   - function: The function where the test container is created (for diagnostics).
///   - operation: The test operation to execute.
/// - Returns: The result of the operation.
/// - Throws: Any error thrown by the operation.
@discardableResult
public func withTestContainer<T>(defaults: TestDefaults? = nil,
                                 unregisteredBehavior: UnregisteredBehavior = .fatalError,
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

    let testContainer = TestContainer(parent: Container(parent: Container.current),
                                      unregisteredBehavior: unregisteredBehavior,
                                      leakedResolutionBehavior: leakedResolutionBehavior,
                                      file: file, line: line, function: function)
    context.container = testContainer
    return try ServiceContext.withValue(context, operation: {
        testContainer.executingTest = true
        defer { testContainer.executingTest = false }
        defaults?.apply(to: testContainer)
        return try operation()
    })
}

/// Executes an asynchronous test operation in an isolated container.
///
/// This is the async counterpart to ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)-1hkwu``.
///
/// ```swift
/// @Test func asyncFeatureWorks() async {
///     await withTestContainer {
///         Container.networkClient.register { MockClient() }
///         let result = await fetchData()
///         #expect(result == .success)
///     }
/// }
/// ```
///
/// - Parameters:
///   - isolation: The actor isolation context.
///   - defaults: Optional ``TestDefaults`` to pre-register in the test container.
///   - unregisteredBehavior: What to do when a factory has no test double. Defaults to ``UnregisteredBehavior/fatalError``.
///   - leakedResolutionBehavior: How to handle resolutions that escape the test scope. Defaults to ``DefaultLeakedResolutionBehavior``.
///   - file: The file where the test container is created (for diagnostics).
///   - line: The line where the test container is created (for diagnostics).
///   - function: The function where the test container is created (for diagnostics).
///   - operation: The async test operation to execute.
/// - Returns: The result of the operation.
/// - Throws: Any error thrown by the operation.
@discardableResult
public func withTestContainer<T>(isolation: isolated(any Actor)? = #isolation,
                                 defaults: TestDefaults? = nil,
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

    let testContainer = TestContainer(parent: Container(parent: Container.current),
                                      unregisteredBehavior: unregisteredBehavior,
                                      leakedResolutionBehavior: leakedResolutionBehavior,
                                      file: file, line: line, function: function)
    context.container = testContainer
    return try await ServiceContext.withValue(context, operation: {
        testContainer.executingTest = true
        defer { testContainer.executingTest = false }
        defaults?.apply(to: testContainer)
        return try await operation()
    })
}
