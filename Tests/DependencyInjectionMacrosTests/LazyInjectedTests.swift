//
//  LazyInjectedTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 7/29/25.
//

import Testing
import MacroTesting

@testable import DependencyInjectionMacros

struct LazyInjectedTests {
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedSyncMacro.self],
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
                @LazyInjected(Container.dependency) private var dependency: Dependency
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
            
                private  let _dependency = LazyInjectedResolver(Container.dependency)
            
                private var $dependency: SyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedSyncThrowingMacro.self],
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
                @LazyInjected(Container.dependency) private var dependency: Result<Dependency, any Error>
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
            
                private  let _dependency = LazyInjectedResolver(Container.dependency)
            
                private var $dependency: SyncThrowingFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedAsyncMacro.self],
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
                @LazyInjected(Container.dependency) private var dependency: Task<Dependency, Never>
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
            
                private  let _dependency = LazyInjectedResolver(Container.dependency)
            
                private var $dependency: AsyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedAsyncThrowingMacro.self],
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
                @LazyInjected(Container.dependency) private var dependency: Task<Dependency, any Error>
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
            
                private  let _dependency = LazyInjectedResolver(Container.dependency)
            
                private var $dependency: AsyncThrowingFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedSyncMacro.self],
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
                @LazyInjected(Container.dependency) private static var dependency: Dependency
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
            
                private static let _dependency = LazyInjectedResolver(Container.dependency)
            
                private static var $dependency: SyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedSyncMacro.self],
          record: .never // Record only missing snapshots
        )
    )
    func macroAssumingInternalSyncFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @LazyInjected(Container.dependency) var dependency: Dependency
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }

            public class Example {
                var dependency: Dependency {
                    get {
                        _dependency.wrappedValue
                    }
                }

                private  let _dependency = LazyInjectedResolver(Container.dependency)

                var $dependency: SyncFactory<Dependency> {
                        _dependency.projectedValue
                }
            }
            """
        }
    }
    
    @Test(
        .macros(
          ["LazyInjected": LazyInjectedSyncMacro.self],
          record: .never // Record only missing snapshots
        )
    )
    func macroWithPublicSyncFactory() {
        assertMacro {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }
            
            public class Example {
                @LazyInjected(Container.dependency) public var dependency: Dependency
            }
            """
        } expansion: {
            """
            class Dependency { }
            extension Container {
                static let dependency = Factory { Dependency() }
            }

            public class Example {
                public var dependency: Dependency {
                    get {
                        _dependency.wrappedValue
                    }
                }

                private  let _dependency = LazyInjectedResolver(Container.dependency)

                public var $dependency: SyncFactory<Dependency> {
                    _dependency.projectedValue
                }
            }
            """
        }
    }
}
