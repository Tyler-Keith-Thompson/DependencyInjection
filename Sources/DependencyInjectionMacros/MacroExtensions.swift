//
//  MacroExtensions.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

extension Macro {
    static func generateInjectedPropertyWrapperPeers(for factoryType: String,
                                                     resolverType: String,
                                                     node: AttributeSyntax,
                                                     providingPeersOf declaration: some DeclSyntaxProtocol,
                                                     in context: some MacroExpansionContext) throws -> [DeclSyntax] {
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
        let factoryExpr = try factoryExpression(from: node)

        let innerType = dependencyType(fromDeclaredType: typeAnnotation.type, factoryType: factoryType)
        let projectedType = "\(factoryType)<\(innerType)>"
        let modifiers = varDecl.modifiers.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
        let modifiersExcludingAccess = modifiers.filter {
            !["public", "internal", "fileprivate", "private"].contains($0)
        }

        let modifierPrefix = modifiersExcludingAccess.joined(separator: " ")
        return [
            DeclSyntax(stringLiteral: "private \(modifierPrefix) let \(privateName) = \(resolverType)(\(factoryExpr), file: #file, line: #line, function: #function)"),
            DeclSyntax(stringLiteral: """
            \(modifiers.joined(separator: " ")) var \(projectedName): \(projectedType) {
                \(privateName).projectedValue
            }
            """)
        ]
    }
    
    static func factoryExpression(from attr: AttributeSyntax) throws -> String {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
              let first = arguments.first else {
            return ""
        }

        return first.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// The dependency type `T` for the projected `$property: <Factory><T>`.
    ///
    /// Only the wrapper the factory kind actually uses is unwrapped:
    /// - `SyncFactory`: the declared type is `T` itself, even when `T` is generic (`AnyClock<Duration>`).
    /// - `SyncThrowingFactory`: the declared type is `Result<T, any Error>`.
    /// - `AsyncFactory` / `AsyncThrowingFactory`: the declared type is `Task<T, Never>` / `Task<T, any Error>`.
    ///
    /// If the declared type is not the expected wrapper it is returned unchanged, and the resolver's
    /// initializer reports the mismatch.
    static func dependencyType(fromDeclaredType declaredType: TypeSyntax, factoryType: String) -> String {
        let trimmedDeclaredType = declaredType.trimmedDescription
        let wrapperNames: Set<String>
        switch factoryType {
        case "SyncThrowingFactory":
            wrapperNames = ["Result", "Swift.Result"]
        case "AsyncFactory", "AsyncThrowingFactory":
            wrapperNames = ["Task", "_Concurrency.Task"]
        default:
            return trimmedDeclaredType
        }
        return firstGenericArgument(of: declaredType, ifNamedOneOf: wrapperNames) ?? trimmedDeclaredType
    }

    /// The first generic argument of `type` (for example `Dictionary<String, Int>` in
    /// `Result<Dictionary<String, Int>, any Error>`) when `type`'s name is one of `names`.
    private static func firstGenericArgument(of type: TypeSyntax, ifNamedOneOf names: Set<String>) -> String? {
        let name: String
        let genericArguments: GenericArgumentClauseSyntax?
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            name = identifier.name.text
            genericArguments = identifier.genericArgumentClause
        } else if let member = type.as(MemberTypeSyntax.self) {
            name = "\(member.baseType.trimmedDescription).\(member.name.text)"
            genericArguments = member.genericArgumentClause
        } else {
            return nil
        }
        guard names.contains(name), let first = genericArguments?.arguments.first else { return nil }
        return first.argument.trimmedDescription
    }
}
