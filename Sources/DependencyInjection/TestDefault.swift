//
//  TestDefault.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 10/18/25.
//

/// A single factory-to-resolver binding for use in test defaults.
///
/// Create instances using the `testValue(_:)` method on any factory type:
///
/// ```swift
/// let loggerDefault = Container.logger.testValue { MockLogger() }
/// ```
///
/// `FactoryDefault` values are collected into ``TestDefault`` groups,
/// which are in turn composed into ``TestDefaults``.
public struct FactoryDefault: @unchecked Sendable {
    fileprivate let apply: (Container) -> Void
    fileprivate init(apply: @escaping (Container) -> Void) { self.apply = apply }
}

public extension SyncFactory {
    /// Creates a ``FactoryDefault`` that registers the given resolver when applied to a test container.
    ///
    /// The registration is deferred -- it only takes effect when the ``FactoryDefault`` is
    /// applied inside a ``withTestContainer(defaults:unregisteredBehavior:leakedResolutionBehavior:file:line:function:operation:)-1hkwu`` call.
    ///
    /// ```swift
    /// let loggerDefault = Container.logger.testValue { MockLogger() }
    /// ```
    ///
    /// - Parameter resolver: The test resolver closure.
    /// - Returns: A ``FactoryDefault`` token.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

public extension SyncThrowingFactory {
    /// Creates a ``FactoryDefault`` that registers the given throwing resolver when applied to a test container.
    ///
    /// - Parameter resolver: The test resolver closure.
    /// - Returns: A ``FactoryDefault`` token.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

public extension AsyncFactory {
    /// Creates a ``FactoryDefault`` that registers the given async resolver when applied to a test container.
    ///
    /// - Parameter resolver: The test resolver closure.
    /// - Returns: A ``FactoryDefault`` token.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

public extension AsyncThrowingFactory {
    /// Creates a ``FactoryDefault`` that registers the given async throwing resolver when applied to a test container.
    ///
    /// - Parameter resolver: The test resolver closure.
    /// - Returns: A ``FactoryDefault`` token.
    func testValue(_ resolver: @escaping Resolver) -> FactoryDefault {
        FactoryDefault { [weak self] c in
            guard let self else { return }
            (self.scope as? ScopeWithCache)?.cache.clear()
            c.addResolver(for: self, resolver: resolver)
        }
    }
}

// MARK: Builders

/// A result builder for composing ``FactoryDefault`` values into a ``TestDefault``.
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

/// A result builder for composing ``TestDefault`` and ``TestDefaults`` values.
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

/// A group of ``FactoryDefault`` values that are applied together.
///
/// Use `TestDefault` to bundle related factory defaults:
///
/// ```swift
/// let networkDefaults = TestDefault {
///     Container.httpClient.testValue { MockHTTPClient() }
///     Container.session.testValue { MockSession() }
/// }
/// ```
public struct TestDefault: Sendable {
    fileprivate let items: [FactoryDefault]
    public init(@TestDefaultBuilder _ make: () -> [FactoryDefault]) { self.items = make() }
    func apply(to c: Container) { items.forEach { $0.apply(c) } }
    fileprivate func erase() -> AnyTestDefaults { AnyTestDefaults { self.apply(to: $0) } }
}

/// A composable collection of ``TestDefault`` and/or other ``TestDefaults``.
///
/// `TestDefaults` supports hierarchical composition, making it easy for libraries
/// to ship reusable test fixtures:
///
/// ```swift
/// extension TestDefaults {
///     static let networkingDefaults = TestDefaults {
///         TestDefault { Container.httpClient.testValue { MockHTTPClient() } }
///         TestDefault { Container.session.testValue { MockSession() } }
///     }
///
///     static let featureDefaults = TestDefaults {
///         .networkingDefaults
///         TestDefault { Container.analytics.testValue { NoopAnalytics() } }
///     }
/// }
/// ```
///
/// Apply defaults to a test container:
///
/// ```swift
/// withTestContainer(defaults: .featureDefaults) {
///     // All defaults are pre-registered
/// }
/// ```
///
/// You can also pass an array literal:
///
/// ```swift
/// withTestContainer(defaults: [.networkingDefaults, .analyticsDefaults]) {
///     // Both sets registered
/// }
/// ```
public struct TestDefaults: Sendable, ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: TestDefaults...) {
        self.groups = elements.map { $0.erase() }
    }

    fileprivate let groups: [AnyTestDefaults]
    public init(@TestDefaultsBuilder _ make: () -> [AnyTestDefaults]) { self.groups = make() }
    func apply(to c: Container) { groups.forEach { $0.apply(to: c) } }
    fileprivate func erase() -> AnyTestDefaults { AnyTestDefaults { self.apply(to: $0) } }
}

/// A type-erased wrapper for ``TestDefault`` or ``TestDefaults``.
public struct AnyTestDefaults: Sendable {
    fileprivate let _apply: @Sendable (Container) -> Void
    fileprivate init(_ apply: @Sendable @escaping (Container) -> Void) { self._apply = apply }
    func apply(to c: Container) { _apply(c) }
}
