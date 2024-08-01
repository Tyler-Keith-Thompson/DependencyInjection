//
//  Cache.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//
import Foundation

public protocol Cache: Sendable {
    func clear()
}

extension Cache {
    var hasValue: Bool {
        (self as? _Cache)?.hasValue ?? false
    }

    func callAsFunction() -> Any? {
        (self as? _Cache)?.callAsFunction()
    }

    func register(_ dependency: Any) {
        (self as? _Cache)?.register(dependency)
    }
}

protocol _Cache {
    var hasValue: Bool { get }

    func callAsFunction() -> Any?

    func register(_ dependency: Any)
}

@available(iOS 13.0, macOS 10.15, tvOS 14.0, watchOS 7.0, *)
final class StrongCache: Cache, _Cache, @unchecked Sendable {
    private var lock = NSRecursiveLock()
    var registeredValue: Any?
    var hasValue: Bool = false

    init() { }

    func callAsFunction() -> Any? {
        defer { lock.unlock() }
        lock.lock()
        return registeredValue
    }

    func register(_ dependency: Any) {
        defer { lock.unlock() }
        lock.lock()
        registeredValue = dependency
        hasValue = true
    }

    public func clear() {
        defer { lock.unlock() }
        lock.lock()
        registeredValue = nil
        hasValue = false
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 14.0, watchOS 7.0, *)
final class WeakCache: Cache, _Cache, @unchecked Sendable {
    private var lock = NSRecursiveLock()
    weak var registeredValue: AnyObject?

    var hasValue: Bool {
        defer { lock.unlock() }
        lock.lock()
        return registeredValue != nil
    }

    init() { }

    func callAsFunction() -> Any? {
        defer { lock.unlock() }
        lock.lock()
        return registeredValue
    }

    func register(_ dependency: Any) {
        defer { lock.unlock() }
        lock.lock()
        registeredValue = dependency as AnyObject
    }

    public func clear() {
        defer { lock.unlock() }
        lock.lock()
        registeredValue = nil
    }
}
