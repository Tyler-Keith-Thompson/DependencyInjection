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
    let testContainerFile: String
    let testContainerLine: UInt
    let testContainerFunction: String
    
    init(parent: Container, unregisteredBehavior: UnregisteredBehavior, file: String = #file, line: UInt = #line, function: String = #function) {
        self.unregisteredBehavior = unregisteredBehavior
        self._parent = parent
        self.testContainerFile = file
        self.testContainerLine = line
        self.testContainerFunction = function
        super.init(parent: parent)
    }
    
    override func resolve<D>(factory: SyncFactory<D>, file: String = #file, line: UInt = #line, function: String = #function) -> D {
        if let registered = storage(for: factory).syncRegistrations.currentResolver() {
            return factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return factory.resolver()
    }
    
    override func resolve<D>(factory: SyncThrowingFactory<D>, file: String = #file, line: UInt = #line, function: String = #function) throws -> D {
        if let registered = storage(for: factory).syncThrowingRegistrations.currentResolver() {
            return try factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return try factory.resolver()
    }

    override func resolve<D>(factory: AsyncFactory<D>, file: String = #file, line: UInt = #line, function: String = #function) async -> D {
        if let registered = storage(for: factory).asyncRegistrations.currentResolver() {
            return await factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
        case .custom(let action):
            action("\(factory)")
        }
        return await factory.resolver()
    }

    override func resolve<D>(factory: AsyncThrowingFactory<D>, file: String = #file, line: UInt = #line, function: String = #function) async throws -> D {
        if let registered = storage(for: factory).asyncThrowingRegistrations.currentResolver() {
            return try await factory.scope.resolve(resolver: registered)
        }
        switch unregisteredBehavior {
        case .fatalError:
            fatalError("Dependency: \(D.self) on factory: \(factory) not registered! Called from \(file):\(line) in \(function). Test container created at \(testContainerFile):\(testContainerLine) in \(testContainerFunction)")
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

public func withTestContainer<T>(unregisteredBehavior: UnregisteredBehavior = .fatalError, file: String = #file, line: UInt = #line, function: String = #function, operation: () throws -> T) rethrows -> T {
    var context = ServiceContext.inUse
    let previous = Container.default.fatalErrorOnResolve
    Container.default.fatalErrorOnResolve = true
    defer { Container.default.fatalErrorOnResolve = previous }
    context.container = TestContainer(parent: Container(parent: Container.current), unregisteredBehavior: unregisteredBehavior, file: file, line: line, function: function)
    return try ServiceContext.withValue(context, operation: operation)
}

public func withTestContainer<T>(isolation: isolated(any Actor)? = #isolation, unregisteredBehavior: UnregisteredBehavior = .fatalError, file: String = #file, line: UInt = #line, function: String = #function, operation: () async throws -> T) async rethrows -> T {
    var context = ServiceContext.inUse
    let previous = Container.default.fatalErrorOnResolve
    Container.default.fatalErrorOnResolve = true
    defer { Container.default.fatalErrorOnResolve = previous }
    context.container = TestContainer(parent: Container(parent: Container.current), unregisteredBehavior: unregisteredBehavior, file: file, line: line, function: function)
    return try await ServiceContext.withValue(context, operation: operation)
}
