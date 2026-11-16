//
//  ConstructorInjectedSyncMacro.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ConstructorInjectedSyncMacro: PeerMacro, AccessorMacro {
    // Emits:
    // - private var _dependency = InjectedResolver(factory: ...)
    // - private var $dependency: SyncFactory<Type> { _dependency.projectedValue }
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try generateInjectedPropertyWrapperPeers(for: "SyncFactory",
                                                 resolverType: "ConstructorInjectedResolver",
                                                 node: node,
                                                 providingPeersOf: declaration,
                                                 in: context)
    }

    // Injects: get { _dependency.wrappedValue }
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        generateInjectedPropertyAccessors(providingAccessorsOf: declaration)
    }
}
