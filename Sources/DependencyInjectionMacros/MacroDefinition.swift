//
//  MacroDefinition.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/27/25.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MyProjectMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] = [
        InjectedSyncMacro.self,
        InjectedSyncThrowingMacro.self,
        InjectedAsyncMacro.self,
        InjectedAsyncThrowingMacro.self,
        ConstructorInjectedSyncMacro.self,
        ConstructorInjectedSyncThrowingMacro.self,
        ConstructorInjectedAsyncMacro.self,
        ConstructorInjectedAsyncThrowingMacro.self,
    ]
}
