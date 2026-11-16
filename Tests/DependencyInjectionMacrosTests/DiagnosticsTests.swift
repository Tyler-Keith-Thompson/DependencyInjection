//
//  DiagnosticsTests.swift
//  DependencyInjection
//

import Testing
import MacroTesting

@testable import DependencyInjectionMacros

@Suite(.macros(
    ["Injected": InjectedSyncMacro.self,
     "LazyInjected": LazyInjectedAsyncMacro.self,
     "ConstructorInjected": ConstructorInjectedSyncThrowingMacro.self],
    record: .never
))
struct DiagnosticsTests {
    @Test func missingTypeAnnotation() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) var service
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) var service
                                                 ┬──────
                                                 ╰─ 🛑 @Injected requires an explicit type annotation, for example 'var service: Service'
            }
            """
        }
    }

    @Test func missingTypeAnnotation_suggestsWrapperForAsyncFactory() {
        assertMacro {
            """
            class Example {
                @LazyInjected(Container.service) var service
            }
            """
        } diagnostics: {
            """
            class Example {
                @LazyInjected(Container.service) var service
                                                     ┬──────
                                                     ╰─ 🛑 @LazyInjected requires an explicit type annotation, for example 'var service: Task<Service, Never>'
            }
            """
        }
    }

    @Test func missingTypeAnnotation_suggestsWrapperForThrowingFactory() {
        assertMacro {
            """
            class Example {
                @ConstructorInjected(Container.service) var service
            }
            """
        } diagnostics: {
            """
            class Example {
                @ConstructorInjected(Container.service) var service
                                                            ┬──────
                                                            ╰─ 🛑 @ConstructorInjected requires an explicit type annotation, for example 'var service: Result<Service, any Error>'
            }
            """
        }
    }

    @Test func letDeclaration() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) let service: Service
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) let service: Service
                                             ┬──
                                             ╰─ 🛑 @Injected requires 'var' because it generates a getter for the property
                                                ✏️ Replace 'let' with 'var'
            }
            """
        } fixes: {
            """
            class Example {
                @Injected(Container.service) var service: Service
            }
            """
        } expansion: {
            """
            class Example {
                var service: Service {
                    get {
                        _service.wrappedValue
                    }
                }

                private  let _service = InjectedResolver(Container.service, file: #file, line: #line, function: #function)

                var $service: SyncFactory<Service> {
                        _service.projectedValue
                }
            }
            """
        }
    }

    @Test func initialValue() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) var service: Service = Service()
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) var service: Service = Service()
                                                                  ┬──────────
                                                                  ╰─ 🛑 @Injected properties can't have an initial value; the value comes from the factory
                                                                     ✏️ Remove the initial value
            }
            """
        } fixes: {
            """
            class Example {
                @Injected(Container.service) var service: Service
            }
            """
        } expansion: {
            """
            class Example {
                var service: Service {
                    get {
                        _service.wrappedValue
                    }
                }

                private  let _service = InjectedResolver(Container.service, file: #file, line: #line, function: #function)

                var $service: SyncFactory<Service> {
                        _service.projectedValue
                }
            }
            """
        }
    }

    @Test func multipleBindings() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) var a: Service, b: Service
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) var a: Service, b: Service
                ┬──────────────────────────────────────────────────────
                ├─ 🛑 accessor macro can only be applied to a single variable
                ╰─ 🛑 peer macro can only be applied to a single variable
            }
            """
        }
    }

    @Test func tuplePattern() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) var (a, b): (Service, Service)
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) var (a, b): (Service, Service)
                                                 ┬─────
                                                 ╰─ 🛑 @Injected requires a simple property name
            }
            """
        }
    }

    @Test func computedProperty() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) var service: Service { Service() }
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) var service: Service { Service() }
                                                                  ┬────────────
                                                                  ╰─ 🛑 @Injected can't be applied to a computed property; remove the accessors
            }
            """
        }
    }

    @Test func notAVariable() {
        assertMacro {
            """
            class Example {
                @Injected(Container.service) func service() { }
            }
            """
        } diagnostics: {
            """
            class Example {
                @Injected(Container.service) func service() { }
                ┬───────────────────────────
                ╰─ 🛑 @Injected can only be applied to a property declared with 'var'
            }
            """
        }
    }
}
