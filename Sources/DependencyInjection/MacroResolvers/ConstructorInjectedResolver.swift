//
//  ConstructorInjectedResolver.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

public final class ConstructorInjectedResolver<Value, Factory: Sendable>: @unchecked Sendable {
    public let wrappedValue: Value
    let factory: Factory
    let cleanup: () -> Void
    public init(_ factory: SyncFactory<Value>, file: String = #file, line: UInt = #line, function: String = #function) where Factory == SyncFactory<Value> {
        wrappedValue = factory(file: file, line: line, function: function)
        self.factory = factory
        cleanup = { }
    }

    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == SyncThrowingFactory<D>, Value == Result<D, any Error> {
        wrappedValue = Result { try factory(file: file, line: line, function: function) }
        self.factory = factory
        cleanup = { }
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == AsyncFactory<D>, Value == Task<D, Never> {
        let task = Task { await factory(file: file, line: line, function: function) }
        wrappedValue = task
        self.factory = factory
        cleanup = task.cancel
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == AsyncThrowingFactory<D>, Value == Task<D, any Error> {
        let task = Task { try await factory(file: file, line: line, function: function) }
        wrappedValue = task
        self.factory = factory
        cleanup = task.cancel
    }
    
    deinit {
        cleanup()
    }
    
    public var projectedValue: Factory {
        factory
    }
}
