//
//  Macros.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/27/25.
//

import DependencyInjectionMacros

public enum InjectedFactoryKind {
    case sync
    case syncThrowing
    case async
    case asyncThrowing
}

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: SyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedSyncMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: SyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedSyncThrowingMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: AsyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedAsyncMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro Injected<T>(_ factory: AsyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedAsyncThrowingMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: SyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedSyncMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: SyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedSyncThrowingMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: AsyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedAsyncMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro ConstructorInjected<T>(_ factory: AsyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "ConstructorInjectedAsyncThrowingMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: SyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedSyncMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: SyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedSyncThrowingMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: AsyncFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedAsyncMacro")

@attached(accessor)
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro LazyInjected<T>(_ factory: AsyncThrowingFactory<T>) = #externalMacro(module: "DependencyInjectionMacros", type: "LazyInjectedAsyncThrowingMacro")
