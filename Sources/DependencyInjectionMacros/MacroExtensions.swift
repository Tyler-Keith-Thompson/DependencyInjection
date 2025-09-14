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
        let type = typeAnnotation.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let factoryExpr = try factoryExpression(from: node)

        // Get the factory type from @Injected<...>(...)
        let innerType = innerTypeForFactory(declaredType: type)
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
    
    static func innerTypeForFactory(declaredType: String) -> String {
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
