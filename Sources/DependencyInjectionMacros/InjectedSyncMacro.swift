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
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindings.count == 1,
              let binding = varDecl.bindings.first,
              let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation else {
            return []
        }

        let name = identifierPattern.identifier.text
        let privateName = "_" + name
        let projectedName = "$" + name
        let type = typeAnnotation.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let factoryExpr = try factoryExpression(from: node)

        // Get the factory type from @Injected<...>(...)
        let factoryType = "SyncFactory"
        let innerType = type
        let projectedType = "\(factoryType)<\(innerType)>"
        let modifiers = varDecl.modifiers.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
        let modifiersExcludingAccess = modifiers.filter {
            !["public", "internal", "fileprivate", "private"].contains($0)
        }

        let modifierPrefix = modifiersExcludingAccess.joined(separator: " ")
        return [
            DeclSyntax(stringLiteral: "private \(modifierPrefix) let \(privateName) = InjectedResolver(\(factoryExpr))"),
            DeclSyntax(stringLiteral: """
            \(modifiers.joined(separator: " ")) var \(projectedName): \(projectedType) {
                \(privateName).projectedValue
            }
            """)
        ]
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

    private static func factoryExpression(from attr: AttributeSyntax) throws -> String {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
              let first = arguments.first else {
            return ""
        }

        return first.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
