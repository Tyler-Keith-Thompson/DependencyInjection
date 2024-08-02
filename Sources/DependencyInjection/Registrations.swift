//
//  Registrations.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//
import Foundation

final class SyncRegistrations<Dependency>: @unchecked Sendable {
    private let lock = NSRecursiveLock()

    private var resolvers = [() -> Dependency]()
    
    func add(resolver: @escaping () -> Dependency) {
        lock.lock()
        defer { lock.unlock() }
        resolvers.append(resolver)
    }
    
    func currentResolver() -> (() -> Dependency)? {
        lock.lock()
        defer { lock.unlock() }
        return resolvers.last
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        resolvers.removeAll()
    }
}

final class SyncThrowingRegistrations<Dependency>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    
    private var resolvers = [() throws -> Dependency]()
    
    func add(resolver: @escaping () throws -> Dependency) {
        lock.lock()
        defer { lock.unlock() }
        resolvers.append(resolver)
    }
    
    func currentResolver() -> (() throws -> Dependency)? {
        lock.lock()
        defer { lock.unlock() }
        return resolvers.last
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        resolvers.removeAll()
    }
}

final class AsyncRegistrations<Dependency>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    
    private var resolvers = [@Sendable () async -> Dependency]()
    
    func add(resolver: @Sendable @escaping () async -> Dependency) {
        lock.lock()
        defer { lock.unlock() }
        resolvers.append(resolver)
    }
    
    func currentResolver() -> (@Sendable () async -> Dependency)? {
        lock.lock()
        defer { lock.unlock() }
        return resolvers.last
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        resolvers.removeAll()
    }
}

final class AsyncThrowingRegistrations<Dependency>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    
    private var resolvers = [@Sendable () async throws -> Dependency]()
    
    func add(resolver: @Sendable @escaping () async throws -> Dependency) {
        lock.lock()
        defer { lock.unlock() }
        resolvers.append(resolver)
    }
    
    func currentResolver() -> (@Sendable () async throws -> Dependency)? {
        lock.lock()
        defer { lock.unlock() }
        return resolvers.last
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        resolvers.removeAll()
    }
}
