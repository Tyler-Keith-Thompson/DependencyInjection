//
//  InjectedPropertyWrapperTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/5/24.
//

import Testing
import DependencyInjection

struct InjectedPropertyWrapperTests {
    @Test func injectedPropertyWrapper_WithSyncFactory_ResolvesEveryTime() async throws {
        class Example {
            @Injected(Container.exampleDependency) var dependency
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
            @Injected(Container.exampleThrowingDependency) var dependency
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
            @Injected(Container.exampleAsyncDependency) var dependency
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
            @Injected(Container.exampleAsyncThrowingDependency) var dependency
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
}

class ExampleDependency { }

class ExampleThrowingDependency {
    init() throws { }
}

class ExampleAsyncDependency {
    init() async { }
}

class ExampleAsyncThrowingDependency {
    init() async throws { }
}

extension Container {
    static let exampleDependency = Factory { ExampleDependency() }
    static let exampleThrowingDependency = Factory { try ExampleThrowingDependency() }
    static let exampleAsyncDependency = Factory { await ExampleAsyncDependency() }
    static let exampleAsyncThrowingDependency = Factory { try await ExampleAsyncThrowingDependency() }
}
