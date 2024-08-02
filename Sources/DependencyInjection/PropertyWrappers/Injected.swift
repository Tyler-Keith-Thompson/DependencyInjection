//
//  Injected.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/2/24.
//

@propertyWrapper
public struct Injected<Value>: Sendable {
    let factory: SyncFactory<Value>
    public init(_ factory: SyncFactory<Value>) {
        self.factory = factory
    }
    
    public var wrappedValue: Value {
        factory()
    }
    
    public var projectedValue: SyncFactory<Value> {
        factory
    }
}
