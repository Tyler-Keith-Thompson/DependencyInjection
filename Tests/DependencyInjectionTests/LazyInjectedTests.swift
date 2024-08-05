//
//  LazyInjectedTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/5/24.
//

import Testing
import DependencyInjection

struct LazyInjectedTests {
    @Test func lazyInjectedPropertyWrapper_WithSyncFactory_ResolvesEveryTime() async throws {
        class Example {
            @LazyInjected(Container.exampleDependency) var dependency
        }
        
        withTestContainer {
            let expected = ExampleDependency()
            var count = 0
            Container.exampleDependency.register {
                count += 1
                return expected
            }
            let example = Example()
            #expect(count == 0)
            #expect(example.dependency === expected)
            #expect(example.dependency === expected)
            #expect(count == 1)
        }
    }
    
    @Test func lazyInjectedPropertyWrapper_WithSyncThrowingFactory_ResolvesEveryTime() async throws {
        class Example {
            @LazyInjected(Container.exampleThrowingDependency) var dependency
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
            #expect(count == 0)
            #expect(try example.dependency.get() === expected)
            #expect(try example.dependency.get() === expected)
            #expect(count == 1)
        }
    }
    
    @Test func lazyInjectedPropertyWrapper_WithAsyncFactory_ResolvesEveryTime() async throws {
        class Example {
            @LazyInjected(Container.exampleAsyncDependency) var dependency
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
            #expect(await test.count == 0)
            #expect(await example.dependency.value === expected)
            #expect(await example.dependency.value === expected)
            #expect(await test.count == 1)
            let example2 = Example()
            _ = await example2.dependency.value
            #expect(await test.count == 2)
        }
    }
    
    @Test func lazyInjectedPropertyWrapper_WithAsyncThrowingFactory_ResolvesEveryTime() async throws {
        class Example {
            @LazyInjected(Container.exampleAsyncThrowingDependency) var dependency
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
            #expect(await test.count == 0)
            #expect(try await example.dependency.value === expected)
            #expect(try await example.dependency.value === expected)
            #expect(await test.count == 1)
            let example2 = Example()
            _ = try await example2.dependency.value
            #expect(await test.count == 2)
        }
    }
}
