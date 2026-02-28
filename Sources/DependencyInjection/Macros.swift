//
//  Macros.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/27/25.
//

// MARK: - @Injected

/// Injects a dependency that is resolved on every property access.
///
/// Apply `@Injected` to a stored property to wire it to a factory. Each time you
/// read the property, the factory resolves a fresh value through ``Container/current``.
///
/// ```swift
/// class OrderService {
///     @Injected(Container.logger) var logger: Logger
///
///     func placeOrder() {
///         logger.log("Order placed")
///     }
/// }
/// ```
///
/// The projected value (`$`) gives access to the underlying factory:
///
/// ```swift
/// $logger.register { FileLogger() }
/// ```
///
/// - Parameter factory: The ``SyncFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: SyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedSyncMacro")

/// Injects a dependency from a throwing factory. The wrapped value type is `Result<T, any Error>`.
///
/// ```swift
/// @Injected(Container.config) var config: Result<Config, any Error>
///
/// func loadConfig() throws -> Config {
///     try config.get()
/// }
/// ```
///
/// - Parameter factory: The ``SyncThrowingFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: SyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedSyncThrowingMacro")

/// Injects a dependency from an async factory. The wrapped value type is `Task<T, Never>`.
///
/// ```swift
/// @Injected(Container.session) var session: Task<URLSession, Never>
///
/// func fetch() async {
///     let s = await session.value
/// }
/// ```
///
/// - Parameter factory: The ``AsyncFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: AsyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedAsyncMacro")

/// Injects a dependency from an async throwing factory. The wrapped value type is `Task<T, any Error>`.
///
/// - Parameter factory: The ``AsyncThrowingFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: AsyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedAsyncThrowingMacro")

// MARK: - @ConstructorInjected

/// Injects a dependency that is resolved once when the owning type is initialized.
///
/// The resolved value is stored and reused for the lifetime of the object.
/// For async factories, the backing task is cancelled in `deinit`.
///
/// ```swift
/// class PaymentProcessor {
///     @ConstructorInjected(Container.gateway) var gateway: PaymentGateway
/// }
/// ```
///
/// - Parameter factory: The ``SyncFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: SyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedSyncMacro")

/// Injects a dependency from a throwing factory at init time. Wrapped value is `Result<T, any Error>`.
///
/// - Parameter factory: The ``SyncThrowingFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: SyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedSyncThrowingMacro")

/// Injects a dependency from an async factory at init time. Wrapped value is `Task<T, Never>`.
/// The task is cancelled in `deinit`.
///
/// - Parameter factory: The ``AsyncFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: AsyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedAsyncMacro")

/// Injects a dependency from an async throwing factory at init time. Wrapped value is `Task<T, any Error>`.
/// The task is cancelled in `deinit`.
///
/// - Parameter factory: The ``AsyncThrowingFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: AsyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedAsyncThrowingMacro")

// MARK: - @LazyInjected

/// Injects a dependency that is resolved on first access and then cached in the instance.
///
/// Unlike ``Injected(_:)-swift.macro``, the resolver is not called until the property is
/// first read. After that, the cached value is returned on subsequent reads (thread-safe).
///
/// ```swift
/// class ReportGenerator {
///     @LazyInjected(Container.formatter) var formatter: DateFormatter
/// }
/// ```
///
/// - Parameter factory: The ``SyncFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: SyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedSyncMacro")

/// Lazy injects from a throwing factory. Wrapped value is `Result<T, any Error>`.
///
/// - Parameter factory: The ``SyncThrowingFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: SyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedSyncThrowingMacro")

/// Lazy injects from an async factory. Wrapped value is `Task<T, Never>`.
/// The async task starts eagerly, but the result is cached on first read.
///
/// - Parameter factory: The ``AsyncFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: AsyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedAsyncMacro")

/// Lazy injects from an async throwing factory. Wrapped value is `Task<T, any Error>`.
///
/// - Parameter factory: The ``AsyncThrowingFactory`` to resolve from.
@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: AsyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedAsyncThrowingMacro")
