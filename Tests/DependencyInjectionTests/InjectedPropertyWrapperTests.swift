//
//  InjectedPropertyWrapperTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/5/24.
//

import Testing
import DependencyInjection
import DependencyInjectionMacros

struct InjectedPropertyWrapperTests {
    @Test func injectedPropertyWrapper_WithSyncFactory_ResolvesEveryTime() async throws {
        class Example {
            @Injected(Container.exampleDependency) var dependency: ExampleDependency
        }
        
        withTestContainer {
            let expected = ExampleDependency()
            var count = 0
            Container.exampleDependency.register {
                count += 1
                return expected
            }
            let example = Example()
            #expect(example.dependency === expected)
            #expect(example.dependency === expected)
            #expect(count == 2)
        }
    }
    
    @Test func injectedPropertyWrapper_WithSyncThrowingFactory_ResolvesEveryTime() async throws {
        class Example {
            @Injected(Container.exampleThrowingDependency, factory: .syncThrowing) var dependency: Result<ExampleThrowingDependency, any Error>
        }
        
        try withTestContainer {
            let expectedResult = Result { try ExampleThrowingDependency() }
            let expected = try expectedResult.get()
            var count = 0
            Container.exampleThrowingDependency.register {
                count += 1
                return try expectedResult.get()
            }
            let example = Example()
            #expect(try example.dependency.get() === expected)
            #expect(try example.dependency.get() === expected)
            #expect(count == 2)
        }
    }
    
    @Test func injectedPropertyWrapper_WithAsyncFactory_ResolvesEveryTime() async throws {
        class Example {
            @Injected(Container.exampleAsyncDependency, factory: .async) var dependency: Task<ExampleAsyncDependency, Never>
        }
        
        await withTestContainer {
            let expectedResult = Task { await ExampleAsyncDependency() }
            let expected = await expectedResult.value
            actor Test {
                var count = 0
                func increment() {
                    count += 1
                }
            }
            let test = Test()
            Container.exampleAsyncDependency.register {
                await test.increment()
                return await expectedResult.value
            }
            let example = Example()
            #expect(await example.dependency.value === expected)
            #expect(await example.dependency.value === expected)
            #expect(await test.count == 2)
        }
    }
    
    @Test func injectedPropertyWrapper_WithAsyncThrowingFactory_ResolvesEveryTime() async throws {
        class Example {
            @Injected(Container.exampleAsyncThrowingDependency, factory: .asyncThrowing) var dependency: Task<ExampleAsyncThrowingDependency, any Error>
        }
        
        try await withTestContainer {
            let expectedResult = Task { try await ExampleAsyncThrowingDependency() }
            let expected = try await expectedResult.value
            actor Test {
                var count = 0
                func increment() {
                    count += 1
                }
            }
            let test = Test()
            Container.exampleAsyncThrowingDependency.register {
                await test.increment()
                return try await expectedResult.value
            }
            let example = Example()
            #expect(try await example.dependency.value === expected)
            #expect(try await example.dependency.value === expected)
            #expect(try await test.count == 2)
        }
    }
    
    @Test func injectedPropertyWrapper_WithSyncFactory_ResolvesEveryTime_EvenWhenStatic_WithSwift6() async throws {
        class Example {
            @Injected(Container.exampleDependency) static var dependency: ExampleDependency
        }
        
        withTestContainer {
            let expected = ExampleDependency()
            var count = 0
            Container.exampleDependency.register {
                count += 1
                return expected
            }
            #expect(Example.dependency === expected)
            #expect(Example.dependency === expected)
            #expect(count == 2)
        }
    }
}

class ExampleDependency: @unchecked Sendable { }

class ExampleThrowingDependency: @unchecked Sendable {
    init() throws { }
}

class ExampleAsyncDependency: @unchecked Sendable {
    init() async { }
}

class ExampleAsyncThrowingDependency: @unchecked Sendable {
    init() async throws { }
}

extension Container {
    static let exampleDependency = Factory { ExampleDependency() }
    static let exampleThrowingDependency = Factory { try ExampleThrowingDependency() }
    static let exampleAsyncDependency = Factory { await ExampleAsyncDependency() }
    static let exampleAsyncThrowingDependency = Factory { try await ExampleAsyncThrowingDependency() }
}
