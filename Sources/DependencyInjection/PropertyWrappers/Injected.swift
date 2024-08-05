//
//  Injected.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/2/24.
//

@propertyWrapper
public struct Injected<Value, Factory: Sendable>: Sendable {
    let factory: Factory
    let getter: @Sendable () -> Value
    public init(_ factory: Factory) where Factory == SyncFactory<Value> {
        getter = { factory() }
        self.factory = factory
    }
    
    public init<D>(_ factory: Factory) where Factory == SyncThrowingFactory<D>, Value == Result<D, any Error> {
        getter = { Result { try factory() } }
        self.factory = factory
    }
    
    public init<D>(_ factory: Factory) where Factory == AsyncFactory<D>, Value == Task<D, Never> {
        getter = { Task { await factory() } }
        self.factory = factory
    }
    
    public init<D>(_ factory: Factory) where Factory == AsyncThrowingFactory<D>, Value == Task<D, any Error> {
        getter = { Task { try await factory() } }
        self.factory = factory
    }
    
    public var wrappedValue: Value {
        getter()
    }
    
    public var projectedValue: Factory {
        factory
    }
}
