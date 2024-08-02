//
//  ConstructorInjected.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/2/24.
//

@propertyWrapper
public struct ConstructorInjected<Value>: @unchecked Sendable {
    public let wrappedValue: Value
    let factory: SyncFactory<Value>
    public init(_ factory: SyncFactory<Value>) {
        self.factory = factory
        wrappedValue = factory()
    }
    
    public var projectedValue: SyncFactory<Value> {
        factory
    }
}
