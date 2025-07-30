//
//  Injected.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/2/24.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InjectedSyncMacro: PeerMacro, AccessorMacro {
    // Emits:
    // - private var _dependency = InjectedResolver(factory: ...)
    // - private var $dependency: SyncFactory<Type> { _dependency.projectedValue }
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try generateInjectedPropertyWrapperPeers(for: "SyncFactory",
                                                 resolverType: "InjectedResolver",
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
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindings.count == 1,
              let binding = varDecl.bindings.first,
              let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return []
        }

        let name = identifierPattern.identifier.text
        let privateName = "_" + name

        return [
            AccessorDeclSyntax("get { \(raw: privateName).wrappedValue }")
        ]
    }
}
