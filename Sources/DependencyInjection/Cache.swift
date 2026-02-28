//
//  Cache.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//
import Foundation

/// A protocol representing a dependency cache that can be cleared.
///
/// Caches are used by ``CachedScope`` and ``SharedScope`` to store resolved instances
/// per container. Each container (including test containers) gets its own cache entry,
/// ensuring test isolation.
///
/// Two built-in implementations are provided:
/// - `StrongCache` -- retains the cached value indefinitely (used by ``CachedScope``)
/// - `WeakCache` -- holds a weak reference that allows deallocation (used by ``SharedScope``)
public protocol Cache: Sendable {
    /// Removes the cached value for the current container.
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
    private final class Entry {
        var registeredValue: Any?
        var hasValue: Bool = false
    }

    private var lock = NSRecursiveLock()
    private var storage = [ObjectIdentifier: Entry]()

    private func entry(for container: Container) -> Entry {
        let id = ObjectIdentifier(container)
        if let e = storage[id] { return e }
        let e = Entry()
        storage[id] = e
        return e
    }

    private func currentContainer() -> Container { Container.current }

    private func searchEntryForRead() -> Entry? {
        var container: Container? = currentContainer()
        // Allow parent fallback except when running under a TestContainer
        let allowParents = !(container is TestContainer)
        while let c = container {
            let id = ObjectIdentifier(c)
            if let e = storage[id], e.hasValue { return e }
            if allowParents {
                container = c.parent
            } else {
                break
            }
        }
        return nil
    }

    var hasValue: Bool {
        defer { lock.unlock() }
        lock.lock()
        return searchEntryForRead() != nil
    }

    func callAsFunction() -> Any? {
        defer { lock.unlock() }
        lock.lock()
        let e = searchEntryForRead() ?? entry(for: currentContainer())
        return e.registeredValue
    }

    func register(_ dependency: Any) {
        defer { lock.unlock() }
        lock.lock()
        let e = entry(for: currentContainer())
        e.registeredValue = dependency
        e.hasValue = true
    }

    public func clear() {
        defer { lock.unlock() }
        lock.lock()
        let e = entry(for: currentContainer())
        e.registeredValue = nil
        e.hasValue = false
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 14.0, watchOS 7.0, *)
final class WeakCache: Cache, _Cache, @unchecked Sendable {
    private final class Entry {
        weak var value: AnyObject?
    }

    private var lock = NSRecursiveLock()
    private var storage = [ObjectIdentifier: Entry]()

    private func entry(for container: Container) -> Entry {
        let id = ObjectIdentifier(container)
        if let e = storage[id] { return e }
        let e = Entry()
        storage[id] = e
        return e
    }

    private func currentContainer() -> Container { Container.current }

    private func searchEntryForRead() -> Entry? {
        var container: Container? = currentContainer()
        let allowParents = !(container is TestContainer)
        while let c = container {
            let id = ObjectIdentifier(c)
            if let e = storage[id], e.value != nil { return e }
            if allowParents {
                container = c.parent
            } else {
                break
            }
        }
        return nil
    }

    var hasValue: Bool {
        defer { lock.unlock() }
        lock.lock()
        return searchEntryForRead()?.value != nil
    }

    func callAsFunction() -> Any? {
        defer { lock.unlock() }
        lock.lock()
        let e = searchEntryForRead() ?? entry(for: currentContainer())
        return e.value
    }

    func register(_ dependency: Any) {
        defer { lock.unlock() }
        lock.lock()
        let e = entry(for: currentContainer())
        e.value = dependency as AnyObject
    }

    public func clear() {
        defer { lock.unlock() }
        lock.lock()
        let e = entry(for: currentContainer())
        e.value = nil
    }
}
