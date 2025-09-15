//
//  LazyInjectedResolver.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

import Foundation

public final class LazyInjectedResolver<Value, Factory: Sendable> {
    let factory: Factory
    let getter: @Sendable () -> Value
    let cleanup: () -> Void
    private let lock = NSRecursiveLock()
    
    public init(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == SyncFactory<Value> {
        getter = { factory(file: file, line: line, function: function) }
        self.factory = factory
        cleanup = { }
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == SyncThrowingFactory<D>, Value == Result<D, any Error> {
        getter = { Result { try factory(file: file, line: line, function: function) } }
        self.factory = factory
        cleanup = { }
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == AsyncFactory<D>, Value == Task<D, Never> {
        let task = Task { await factory(file: file, line: line, function: function) }
        getter = { task }
        self.factory = factory
        cleanup = task.cancel
    }
    
    public init<D>(_ factory: Factory, file: String = #file, line: UInt = #line, function: String = #function) where Factory == AsyncThrowingFactory<D>, Value == Task<D, any Error> {
        let task = Task { try await factory(file: file, line: line, function: function) }
        getter = { task }
        self.factory = factory
        cleanup = task.cancel
    }
    
    private var _wrappedValue: Value?
    
    public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            
            if let _wrappedValue {
                return _wrappedValue
            }
            
            let dependency = getter()
            _wrappedValue = dependency
            return dependency
        }
    }

    public var projectedValue: Factory {
        factory
    }
}
