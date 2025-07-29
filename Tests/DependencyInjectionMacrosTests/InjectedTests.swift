//
//  InjectedTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/27/25.
//

import Testing
import MacroTesting

@testable import DependencyInjectionMacros

struct InjectedTests {
    @Test(
        .macros(
          ["Injected": InjectedSyncMacro.self],
          record: .never // Record only missing snapshots
        )
    )
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
            
                private let _dependency = InjectedResolver(Container.dependency)
            
                private var $dependency: SyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["Injected": InjectedSyncThrowingMacro.self],
          record: .never // Record only missing snapshots
        )
    )
    func macroSpecifyingSyncThrowingFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @Injected(Container.dependency) private var dependency: Result<Dependency, any Error>
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
            
                private let _dependency = InjectedResolver(Container.dependency)
            
                private var $dependency: SyncThrowingFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["Injected": InjectedAsyncMacro.self],
          record: .never // Record only missing snapshots
        )
    )
    func macroSpecifyingAsyncFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @Injected(Container.dependency) private var dependency: Task<Dependency, Never>
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                private var dependency: Task<Dependency, Never> {
                    get {
                        _dependency.wrappedValue
                    }
                }
            
                private let _dependency = InjectedResolver(Container.dependency)
            
                private var $dependency: AsyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["Injected": InjectedAsyncThrowingMacro.self],
          record: .never // Record only missing snapshots
        )
    )
    func macroSpecifyingAsyncThrowingFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @Injected(Container.dependency) private var dependency: Task<Dependency, any Error>
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                private var dependency: Task<Dependency, any Error> {
                    get {
                        _dependency.wrappedValue
                    }
                }
            
                private let _dependency = InjectedResolver(Container.dependency)
            
                private var $dependency: AsyncThrowingFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["Injected": InjectedSyncMacro.self],
          record: .never // Record only missing snapshots
        )
    )
    func macroAssumingStaticSyncFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @Injected(Container.dependency) private static var dependency: Dependency
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                private static var dependency: Dependency {
                    get {
                        _dependency.wrappedValue
                    }
                }
            
                private static let _dependency = InjectedResolver(Container.dependency)
            
                private static var $dependency: SyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
}
