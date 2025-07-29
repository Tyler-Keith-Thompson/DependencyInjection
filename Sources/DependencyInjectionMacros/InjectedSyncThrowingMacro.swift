//
//  InjectedSyncThrowingMacro.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InjectedSyncThrowingMacro: PeerMacro, AccessorMacro {
    // Emits:
    // - private var _dependency = InjectedResolver(factory: ...)
    // - private var $dependency: SyncThrowingFactory<Type> { _dependency.projectedValue }
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

        let factoryType = "SyncThrowingFactory"
        let innerType = innerTypeForFactory(declaredType: type)
        let projectedType = "\(factoryType)<\(innerType)>"
        let modifiersExcludingAccess = varDecl.modifiers.filter {
            !["public", "internal", "fileprivate", "private"].contains($0.name.text)
        }

        let modifierPrefix = "private " + modifiersExcludingAccess.map(\.description).joined(separator: " ")
        return [
            DeclSyntax(stringLiteral: "\(modifierPrefix)let \(privateName) = InjectedResolver(\(factoryExpr))"),
            DeclSyntax(stringLiteral: """
            \(modifierPrefix)var \(projectedName): \(projectedType) {
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
    
    private static func innerTypeForFactory(declaredType: String) -> String {
        guard let genericStart = declaredType.firstIndex(of: "<"),
              let genericEnd = declaredType.lastIndex(of: ">") else {
            return declaredType
        }

        let inner = declaredType[declaredType.index(after: genericStart)..<genericEnd]
        return inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? declaredType
    }
}
