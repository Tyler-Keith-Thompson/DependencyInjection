//
//  InjectedTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/27/25.
//

import Testing
import MacroTesting

@testable import DependencyInjectionMacros

@Suite(
  .macros(
    ["Injected": InjectedMacro.self],
    record: .never // Record only missing snapshots
  )
)
struct InjectedTests {
    @Test
    func macroAssumingSyncFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @Injected(Container.dependency) private var dependency: Dependency
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                private var dependency: Dependency {
                    get {
                        _dependency.wrappedValue
                    }
                }
            
                private var _dependency = InjectedResolver(Container.dependency)
            
                private var $dependency: SyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test
    func macroSpecifyingSyncThrowingFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @Injected(Container.dependency, factory: .syncThrowing) private var dependency: Result<Dependency, any Error>
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                private var dependency: Result<Dependency, any Error> {
                    get {
                        _dependency.wrappedValue
                    }
                }
            
                private var _dependency = InjectedResolver(Container.dependency)
            
                private var $dependency: SyncThrowingFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
}
