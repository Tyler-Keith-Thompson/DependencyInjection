//
//  TestDefault.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 10/18/25.
//

public struct FactoryDefault: @unchecked Sendable {
    fileprivate let apply: (Container) -> Void
    fileprivate init(apply: @escaping (Container) -> Void) { self.apply = apply }
}

public extension SyncFactory {
    // Intentionally returns a token; the side effect (register) happens
    // only when TestDefault/TestDefaults are applied in a test scope.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

public extension SyncThrowingFactory {
    // Intentionally returns a token; the side effect (register) happens
    // only when TestDefault/TestDefaults are applied in a test scope.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

public extension AsyncFactory {
    // Intentionally returns a token; the side effect (register) happens
    // only when TestDefault/TestDefaults are applied in a test scope.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

public extension AsyncThrowingFactory {
    // Intentionally returns a token; the side effect (register) happens
    // only when TestDefault/TestDefaults are applied in a test scope.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

// MARK: Builders

@resultBuilder
public enum TestDefaultBuilder {
    public static func buildBlock(_ parts: [FactoryDefault]...) -> [FactoryDefault] {
        parts.flatMap { $0 }
    }
    public static func buildExpression(_ value: FactoryDefault) -> [FactoryDefault] { [value] }
    public static func buildOptional(_ component: [FactoryDefault]?) -> [FactoryDefault] { component ?? [] }
    public static func buildEither(first: [FactoryDefault]) -> [FactoryDefault] { first }
    public static func buildEither(second: [FactoryDefault]) -> [FactoryDefault] { second }
}

@resultBuilder
public enum TestDefaultsBuilder {
    public static func buildBlock(_ parts: [AnyTestDefaults]...) -> [AnyTestDefaults] {
        parts.flatMap { $0 }
    }
    public static func buildExpression(_ value: TestDefault) -> [AnyTestDefaults] { [value.erase()] }
    public static func buildExpression(_ value: TestDefaults) -> [AnyTestDefaults] { [value.erase()] }
    public static func buildOptional(_ component: [AnyTestDefaults]?) -> [AnyTestDefaults] { component ?? [] }
    public static func buildEither(first: [AnyTestDefaults]) -> [AnyTestDefaults] { first }
    public static func buildEither(second: [AnyTestDefaults]) -> [AnyTestDefaults] { second }
}

// MARK: Composable containers

public struct TestDefault: Sendable {
    fileprivate let items: [FactoryDefault]
    public init(@TestDefaultBuilder _ make: () -> [FactoryDefault]) { self.items = make() }
    func apply(to c: Container) { items.forEach { $0.apply(c) } }
    fileprivate func erase() -> AnyTestDefaults { AnyTestDefaults { self.apply(to: $0) } }
}

public struct TestDefaults: Sendable, ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: TestDefaults...) {
        self.groups = elements.map { $0.erase() }
    }
    
    fileprivate let groups: [AnyTestDefaults]
    public init(@TestDefaultsBuilder _ make: () -> [AnyTestDefaults]) { self.groups = make() }
    func apply(to c: Container) { groups.forEach { $0.apply(to: c) } }
    fileprivate func erase() -> AnyTestDefaults { AnyTestDefaults { self.apply(to: $0) } }
}

public struct AnyTestDefaults: Sendable {
    fileprivate let _apply: @Sendable (Container) -> Void
    fileprivate init(_ apply: @Sendable @escaping (Container) -> Void) { self._apply = apply }
    func apply(to c: Container) { _apply(c) }
}
