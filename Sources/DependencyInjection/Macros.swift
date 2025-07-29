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
public macro Injected(_ factory: Any, factory type: InjectedFactoryKind = .sync) = #externalMacro(module: "DependencyInjectionMacros", type: "InjectedMacro")
