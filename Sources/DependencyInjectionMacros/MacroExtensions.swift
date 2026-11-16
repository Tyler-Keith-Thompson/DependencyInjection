//
//  MacroExtensions.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension Macro {
    static func generateInjectedPropertyWrapperPeers(for factoryType: String,
                                                     resolverType: String,
                                                     node: AttributeSyntax,
                                                     providingPeersOf declaration: some DeclSyntaxProtocol,
                                                     in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let property = InjectedProperty(declaration: declaration,
                                              attribute: node,
                                              factoryType: factoryType,
                                              diagnosingIn: context) else {
            return []
        }
        let varDecl = property.declaration
        let typeAnnotation = property.typeAnnotation

        let name = property.name
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
    
    /// The `get` accessor shared by every injection macro. Invalid declarations produce no
    /// accessors here; the peer expansion reports why.
    static func generateInjectedPropertyAccessors(providingAccessorsOf declaration: some DeclSyntaxProtocol) -> [AccessorDeclSyntax] {
        guard let property = InjectedProperty(declaration: declaration) else { return [] }
        return [
            AccessorDeclSyntax("get { \(raw: "_" + property.name).wrappedValue }")
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

/// A property declaration that an injection macro can expand.
///
/// The macros turn `var name: Type` into a computed property backed by a generated
/// `_name` resolver, so the declaration must be a single, stored-looking `var` with a
/// simple name, an explicit type and no initial value.
struct InjectedProperty {
    let declaration: VariableDeclSyntax
    let name: String
    let typeAnnotation: TypeAnnotationSyntax

    /// Validates `declaration`. When `context` is given, each problem is reported as an
    /// error diagnostic on the offending syntax.
    init?(declaration: some DeclSyntaxProtocol,
          attribute: AttributeSyntax? = nil,
          factoryType: String? = nil,
          diagnosingIn context: (any MacroExpansionContext)? = nil) {
        let macroName = "@" + (attribute?.attributeName.trimmedDescription ?? "Injected")
        func diagnose(_ node: some SyntaxProtocol, _ id: String, _ message: String, fixIts: [FixIt] = []) {
            context?.diagnose(Diagnostic(node: Syntax(node),
                                         message: InjectionMacroDiagnostic(id: id, message: message),
                                         fixIts: fixIts))
        }
        let attributeNode = Syntax(attribute) ?? Syntax(declaration)

        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            diagnose(attributeNode, "not-a-variable",
                     "\(macroName) can only be applied to a property declared with 'var'")
            return nil
        }

        var isValid = true

        if varDecl.bindingSpecifier.tokenKind == .keyword(.let) {
            isValid = false
            diagnose(varDecl.bindingSpecifier, "requires-var",
                     "\(macroName) requires 'var' because it generates a getter for the property",
                     fixIts: [FixIt(message: InjectionMacroFixIt(id: "use-var", message: "Replace 'let' with 'var'"),
                                    changes: [.replace(oldNode: Syntax(varDecl.bindingSpecifier),
                                                       newNode: Syntax(varDecl.bindingSpecifier.with(\.tokenKind, .keyword(.var))))])])
        }

        guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
            diagnose(varDecl.bindings, "multiple-bindings",
                     "\(macroName) can only be applied to one property at a time; declare each injected property separately")
            return nil
        }

        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            diagnose(binding.pattern, "not-an-identifier",
                     "\(macroName) requires a simple property name")
            return nil
        }

        if binding.accessorBlock != nil {
            isValid = false
            diagnose(binding.accessorBlock!, "has-accessors",
                     "\(macroName) can't be applied to a computed property; remove the accessors")
        }

        if let initializer = binding.initializer {
            isValid = false
            diagnose(initializer, "has-initializer",
                     "\(macroName) properties can't have an initial value; the value comes from the factory",
                     fixIts: [FixIt(message: InjectionMacroFixIt(id: "remove-initializer", message: "Remove the initial value"),
                                    changes: [.replace(oldNode: Syntax(binding),
                                                       newNode: Syntax(binding.with(\.initializer, nil)
                                                                         .with(\.typeAnnotation, binding.typeAnnotation?.trimmed)))])])
        }

        guard let typeAnnotation = binding.typeAnnotation else {
            diagnose(binding.pattern, "missing-type-annotation",
                     "\(macroName) requires an explicit type annotation, for example 'var \(identifier.identifier.text): \(Self.exampleType(for: factoryType))'")
            return nil
        }

        guard isValid else { return nil }
        self.declaration = varDecl
        self.name = identifier.identifier.text
        self.typeAnnotation = typeAnnotation
    }

    private static func exampleType(for factoryType: String?) -> String {
        switch factoryType {
        case "SyncThrowingFactory": return "Result<Service, any Error>"
        case "AsyncFactory": return "Task<Service, Never>"
        case "AsyncThrowingFactory": return "Task<Service, any Error>"
        default: return "Service"
        }
    }
}

struct InjectionMacroDiagnostic: DiagnosticMessage {
    let id: String
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "DependencyInjectionMacros", id: id) }
    var severity: DiagnosticSeverity { .error }
}

struct InjectionMacroFixIt: FixItMessage {
    let id: String
    let message: String
    var fixItID: MessageID { MessageID(domain: "DependencyInjectionMacros", id: id) }
}
