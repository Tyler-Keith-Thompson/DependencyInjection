//
//  InjectedResolver.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/28/25.
//

public struct InjectedResolver<Value, Factory: Sendable>: Sendable {
    let factory: Factory
    let getter: @Sendable () -> Value
    public init(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == SyncFactory<Value> {
        getter = { factory(file: file, line: line, function: function) }
        self.factory = factory
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == SyncThrowingFactory<D>, Value == Result<D, any Error> {
        getter = { Result { try factory(file: file, line: line, function: function) } }
        self.factory = factory
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == AsyncFactory<D>, Value == Task<D, Never> {
        getter = { Task { await factory(file: file, line: line, function: function) } }
        self.factory = factory
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == AsyncThrowingFactory<D>, Value == Task<D, any Error> {
        getter = { Task { try await factory(file: file, line: line, function: function) } }
        self.factory = factory
    }
    
    public var wrappedValue: Value {
        getter()
    }
    
    public var projectedValue: Factory {
        factory
    }
}
