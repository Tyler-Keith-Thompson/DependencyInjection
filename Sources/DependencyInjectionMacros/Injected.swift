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

public struct InjectedMacro: PeerMacro, AccessorMacro {
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
        let type = typeAnnotation.type.description.trimmed
        let factoryExpr = try factoryExpression(from: node)

        // Get the factory type from @Injected<...>(...)
        let factoryType = extractFactoryType(from: node)
        let innerType = innerTypeForFactory(factoryType, declaredType: type)
        let projectedType = "\(factoryType)<\(innerType)>"

        return [
            DeclSyntax(stringLiteral: "private var \(privateName) = InjectedResolver(\(factoryExpr))"),
            DeclSyntax(stringLiteral: """
            private var \(projectedName): \(projectedType) {
                \(privateName).projectedValue
            }
            """)
        ]
//        return [
//            DeclSyntax(stringLiteral: "private var \(privateName) = InjectedResolver(\(factoryExpr))"),
//            DeclSyntax(stringLiteral: """
//            private var \(projectedName): SyncFactory<\(type)> {
//                \(privateName).projectedValue
//            }
//            """)
//        ]
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

        return first.expression.description.trimmed
    }
    
    private static func extractFactoryType(from attr: AttributeSyntax) -> String {
        guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else {
            return "SyncFactory"
        }

        let secondArgExpr = args.dropFirst().first?.expression

        if let memberAccess = secondArgExpr?.as(MemberAccessExprSyntax.self) {
            switch memberAccess.declName.trimmedDescription {
            case "sync": return "SyncFactory"
            case "syncThrowing": return "SyncThrowingFactory"
            case "async": return "AsyncFactory"
            case "asyncThrowing": return "AsyncThrowingFactory"
            default: return "SyncFactory"
            }
        }

        return "SyncFactory"
    }
    
    private static func innerTypeForFactory(_ factoryType: String, declaredType: String) -> String {
        func extractFirstGenericArgument(from type: String) -> String? {
            guard let genericStart = type.firstIndex(of: "<"),
                  let genericEnd = type.lastIndex(of: ">") else {
                return nil
            }

            let inner = type[type.index(after: genericStart)..<genericEnd]
            return inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch factoryType {
        case "SyncThrowingFactory" where declaredType.starts(with: "Result<"):
            return extractFirstGenericArgument(from: declaredType) ?? declaredType

        case "AsyncFactory" where declaredType.starts(with: "Task<"), "AsyncThrowingFactory" where declaredType.starts(with: "Task<"):
            return extractFirstGenericArgument(from: declaredType) ?? declaredType

        default:
            return declaredType
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
