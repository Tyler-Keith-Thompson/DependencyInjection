//
//  LazyInjected.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/2/24.
//

import Foundation

@propertyWrapper
public final class LazyInjected<Value> {
    let factory: SyncFactory<Value>
    private let lock = NSRecursiveLock()
    
    public init(_ factory: SyncFactory<Value>) {
        self.factory = factory
    }

    private var _wrappedValue: Value?
    
    public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            
            if let _wrappedValue {
                return _wrappedValue
            }
            
            let dependency = factory()
            _wrappedValue = dependency
            return dependency
        }
    }

    public var projectedValue: SyncFactory<Value> {
        factory
    }
}
