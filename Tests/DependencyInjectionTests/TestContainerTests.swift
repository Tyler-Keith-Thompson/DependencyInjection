//
//  TestContainerTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Testing
import Dispatch
import Foundation
@testable import DependencyInjection

struct TestContainerTests {
    nonisolated(unsafe) let failTestBehavior = UnregisteredBehavior.custom {
        Issue.record("Dependency for factory: \($0) not registered!")
    }
    
    @Test func withTestContainerOverridesDoNotLeakAcrossTests_whenUsingCachedScope() async throws {
        class Super { }
        enum Globals {
            static let service = Factory(scope: .cached) { Super() }
        }

        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let testValue = Super()
            Globals.service.register { testValue }
            #expect(Globals.service() === testValue)
        }

        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let another = Super()
            Globals.service.register { another }
            #expect(Globals.service() === another)
        }
    }

    @Test func sharedScopeInterferenceAcrossConcurrentWithTestContainerBlocks() async throws {
        final class Ref: NSObject { }
        enum Globals {
            static let sharedDep = Factory(scope: .shared) { Ref() }
        }

        let aReady = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)

        // This reproduces the same cross-container interference for .shared
        async let a: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            let aRef = Ref()
            Globals.sharedDep.register { aRef }
            aReady.signal()
            let first = Globals.sharedDep()
            #expect(first === aRef)
            _ = bDone.wait(timeout: .now() + 1)
            let second = Globals.sharedDep()
            #expect(second === aRef)
        }

        async let b: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            _ = aReady.wait(timeout: .now() + 1)
            let bRef = Ref()
            Globals.sharedDep.register { bRef }
            let resolved = Globals.sharedDep()
            #expect(resolved === bRef)
            bDone.signal()
        }

        _ = await (a, b)
    }
    @Test func staticCachedFactoryWithTwoWithTestContainerBlocks_mirrorsRealProject() async throws {
        class MyDep { }
        enum Globals {
            static let cachedDep = Factory(scope: .cached) { MyDep() }
        }

        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let testValue = MyDep()
            Globals.cachedDep.register { testValue }
            #expect(Globals.cachedDep() === testValue)
        }

        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let testValue = MyDep()
            Globals.cachedDep.register { testValue }
            #expect(Globals.cachedDep() === testValue)
        }
    }

    @Test func cachedFactoryPrimedBeforeWithTestContainer_isClearedOnRegister() async throws {
        class MyDep { }
        enum Globals {
            static let cachedDep = Factory(scope: .cached) { MyDep() }
        }

        withNestedContainer {
            // Prime cache outside test container
            _ = Globals.cachedDep()
            
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                let testValue = MyDep()
                Globals.cachedDep.register { testValue }
                #expect(Globals.cachedDep() === testValue)
            }
        }
    }

    @Test func cachedScopeInterferenceAcrossConcurrentWithTestContainerBlocks_Sync() async throws {
        class MyDep { }
        enum Globals {
            static let cachedDep = Factory(scope: .cached) { MyDep() }
        }

        let aReady = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)

        // This should pass with per-container cached scope, using nested containers to avoid global fatal flag
        do {
            async let a: Void = withTestContainer {
                let depA = MyDep()
                Globals.cachedDep.register { depA }
                aReady.signal()
                let first = Globals.cachedDep()
                #expect(first === depA)
                // Wait for B to register and resolve, which clears and overwrites the global cache
                _ = bDone.wait(timeout: .now() + 1)
                // This can fail with StrongCache because cache is shared across containers
                let second = Globals.cachedDep()
                #expect(second === depA)
            }

            async let b: Void = withTestContainer {
                _ = aReady.wait(timeout: .now() + 1)
                let depB = MyDep()
                Globals.cachedDep.register { depB }
                let resolved = Globals.cachedDep()
                #expect(resolved === depB)
                bDone.signal()
            }

            _ = await (a, b)
        }
    }
    
    @Test func cachedScopeInterferenceAcrossConcurrentWithTestContainerBlocks_SyncThrowing() async throws {
        class MyDep { }
        enum Globals {
            static let cachedDep = Factory(scope: .cached) { () throws -> MyDep in MyDep() }
        }

        let aReady = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)

        // This should pass with per-container cached scope, using nested containers to avoid global fatal flag
        do {
            async let a: Void = withTestContainer {
                let depA = MyDep()
                Globals.cachedDep.register { depA }
                aReady.signal()
                let first = try Globals.cachedDep()
                #expect(first === depA)
                // Wait for B to register and resolve, which clears and overwrites the global cache
                _ = bDone.wait(timeout: .now() + 1)
                // This can fail with StrongCache because cache is shared across containers
                let second = try Globals.cachedDep()
                #expect(second === depA)
            }

            async let b: Void = withTestContainer {
                _ = aReady.wait(timeout: .now() + 1)
                let depB = MyDep()
                Globals.cachedDep.register { depB }
                let resolved = try Globals.cachedDep()
                #expect(resolved === depB)
                bDone.signal()
            }

            _ = try await (a, b)
        }
    }
    
    @Test func cachedScopeInterferenceAcrossConcurrentWithTestContainerBlocks_Async() async throws {
        final class MyDep: Sendable { }
        enum Globals {
            nonisolated(unsafe) static let cachedDep = Factory(scope: .cached) { () async -> MyDep in MyDep() }
        }

        // Use continuations for coordination
        let (aReadyStream, aReadyContinuation) = AsyncStream.makeStream(of: Void.self)
        let (bDoneStream, bDoneContinuation) = AsyncStream.makeStream(of: Void.self)

        // This should pass with per-container cached scope, using nested containers to avoid global fatal flag
        do {
            async let a: Void = withTestContainer {
                let depA = MyDep()
                Globals.cachedDep.register { depA }
                aReadyContinuation.yield(())
                let first = await Globals.cachedDep()
                #expect(first === depA)
                // Wait for B to register and resolve, which clears and overwrites the global cache
                for await _ in bDoneStream { break }
                // This can fail with StrongCache because cache is shared across containers
                let second = await Globals.cachedDep()
                #expect(second === depA)
            }

            async let b: Void = withTestContainer {
                for await _ in aReadyStream { break }
                let depB = MyDep()
                Globals.cachedDep.register { depB }
                let resolved = await Globals.cachedDep()
                #expect(resolved === depB)
                bDoneContinuation.yield(())
            }

            _ = await (a, b)
        }
    }
    
    @Test func cachedScopeInterferenceAcrossConcurrentWithTestContainerBlocks_AsyncThrowing() async throws {
        final class MyDep: Sendable { }
        enum Globals {
            nonisolated(unsafe) static let cachedDep = Factory(scope: .cached) { () async throws -> MyDep in MyDep() }
        }

        // Use continuations for coordination
        let (aReadyStream, aReadyContinuation) = AsyncStream.makeStream(of: Void.self)
        let (bDoneStream, bDoneContinuation) = AsyncStream.makeStream(of: Void.self)

        // This should pass with per-container cached scope, using nested containers to avoid global fatal flag
        do {
            async let a: Void = withTestContainer {
                let depA = MyDep()
                Globals.cachedDep.register { depA }
                aReadyContinuation.yield(())
                let first = try await Globals.cachedDep()
                #expect(first === depA)
                // Wait for B to register and resolve, which clears and overwrites the global cache
                for await _ in bDoneStream { break }
                // This can fail with StrongCache because cache is shared across containers
                let second = try await Globals.cachedDep()
                #expect(second === depA)
            }

            async let b: Void = withTestContainer {
                for await _ in aReadyStream { break }
                let depB = MyDep()
                Globals.cachedDep.register { depB }
                let resolved = try await Globals.cachedDep()
                #expect(resolved === depB)
                bDoneContinuation.yield(())
            }

            _ = try await (a, b)
        }
    }
    
    // Keep the original test for backward compatibility
    @Test func cachedScopeInterferenceAcrossConcurrentWithTestContainerBlocks() async throws {
        class MyDep { }
        enum Globals {
            static let cachedDep = Factory(scope: .cached) { MyDep() }
        }

        let aReady = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)

        // This should pass with per-container cached scope, using nested containers to avoid global fatal flag
        do {
            async let a: Void = withNestedContainer {
                let depA = MyDep()
                Globals.cachedDep.register { depA }
                aReady.signal()
                let first = Globals.cachedDep()
                #expect(first === depA)
                // Wait for B to register and resolve, which clears and overwrites the global cache
                _ = bDone.wait(timeout: .now() + 1)
                // This can fail with StrongCache because cache is shared across containers
                let second = Globals.cachedDep()
                #expect(second === depA)
            }

            async let b: Void = withNestedContainer {
                _ = aReady.wait(timeout: .now() + 1)
                let depB = MyDep()
                Globals.cachedDep.register { depB }
                let resolved = Globals.cachedDep()
                #expect(resolved === depB)
                bDone.signal()
            }

            _ = await (a, b)
        }
    }
    
    @Test func factoryWeakCacheIsResetAfterRegistration() async throws {
        class Super { }
        let factory = Factory(scope: .shared) { Super() }
        
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let val = Super()
            factory.register { val }
            let resolved = factory()
            #expect(resolved === val)
            let val2 = Super()
            factory.register { val2 }
            #expect(factory() === val2)
        }
    }
    
    @Test func factoryStrongCacheIsResetAfterRegistration() async throws {
        class Super { }
        let factory = Factory(scope: .cached) { Super() }
        
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let val = Super()
            factory.register { val }
            let resolved = factory()
            #expect(resolved === val)
            let val2 = Super()
            factory.register { val2 }
            #expect(factory() === val2)
        }
    }
    
    class ICannotBelievePeopleDoThis {
        @discardableResult init(factory: SyncFactory<Bool>) {
            Task {
                try await Task.sleep(nanoseconds: 100000)
                #expect(factory() == true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) {
                #expect(factory() == true)
            }
        }
    }
    
    #if canImport(Darwin)
    @Test func whatIfWeCouldPreventLeaks_ThatWouldBeReallyCool() async throws {
        let factory = Factory { true }
        withTestContainer(unregisteredBehavior: failTestBehavior,
                          leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
            // Make it visible to ALL capture paths for the duration of the scope:
            ICannotBelievePeopleDoThis(factory: factory)
        }
        
        try await withTestContainer(unregisteredBehavior: failTestBehavior,
                                    leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) { // second test
            try await Task {
                try await Task.sleep(nanoseconds: 10000000)
            }.value // wait for it
        }
    }
    
    @Test func withNestedContainer_InsideTestContainer_DoesNotCrash() async throws {
        let factory = Factory { "test-value" }
        
        withTestContainer(unregisteredBehavior: failTestBehavior,
                          leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
            // This used to crash because withNestedContainer created a regular Container 
            // that would hit fatalErrorOnResolve instead of using leak detection
            withNestedContainer {
                // Register the factory in THIS container - TestContainers should be isolated
                factory.register { "registered-value" }
                let result = factory()
                #expect(result == "registered-value")
            }
        }
    }
    
    @Test func withNestedContainer_InsideTestContainer_PreservesLeakDetection() async throws {
        let factory = Factory { true }
        
        await withTestContainer(unregisteredBehavior: failTestBehavior,
                               leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
            // This should trigger leak detection through the nested container
            await withNestedContainer {
                // Register the factory in THIS nested container - TestContainers are isolated
                factory.register { true }
                // This will cause a leak that should be handled gracefully
                ICannotBelievePeopleDoThis(factory: factory)
            }
        }
    }

    @Test func withTestContainer_InsideNestedContainer_DoesNotCrash() async throws {
        let factory = Factory { "test-value" }
        
        withNestedContainer {
            withTestContainer(unregisteredBehavior: failTestBehavior,
                          leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
                // This used to crash because withNestedContainer created a regular Container 
                // that would hit fatalErrorOnResolve instead of using leak detection
                // Register the factory in THIS container - TestContainers should be isolated
                factory.register { "registered-value" }
                let result = factory()
                #expect(result == "registered-value")
            }
        }
    }
    
    @Test func withTestContainer_InsideNestedContainer_PreservesLeakDetection() async throws {
        let factory = Factory { true }
        
        await withNestedContainer {
            await withTestContainer(unregisteredBehavior: failTestBehavior,
                               leakedResolutionBehavior: BestEffortLeakedResolutionBehavior()) {
                // This should trigger leak detection through the nested container
                // Register the factory in THIS nested container - TestContainers are isolated
                factory.register { true }
                // This will cause a leak that should be handled gracefully
                ICannotBelievePeopleDoThis(factory: factory)
            }
        }
    }

    @Test func withTestContainer_OutsideNestedContainer_PreservesUnregisteredBehavior() {
        let factory = Factory { true }
        withKnownIssue {
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                withNestedContainer {
                    factory() // this should fail
                    return
                }
            }
        }
    }
    
    @Test func concurrentWithTestContainer_RaceConditionFixed() async throws {
        #if DEBUG
        // This test verifies that the race condition in concurrent withTestContainer calls
        // has been fixed with atomic reference counting
        
        // Start with fatalErrorOnResolve = false
        let originalValue = Container.default.fatalErrorOnResolve
        Container.default.fatalErrorOnResolve = false
        defer { Container.default.fatalErrorOnResolve = originalValue }
        
        let factory1 = Factory { "task1" }
        let factory2 = Factory { "task2" }
        
        // Run multiple iterations to increase chance of hitting the race condition
        for _ in 0..<10 {
            // Reset to false before each iteration
            Container.default.fatalErrorOnResolve = false
            
            // Start two concurrent withTestContainer calls with precise timing
            let task1 = Task {
                do {
                    try await withTestContainer(unregisteredBehavior: .fatalError) {
                        factory1.register { "task1" }
                        // Task1 runs briefly then exits, which will restore fatalErrorOnResolve to false
                        try await Task.sleep(nanoseconds: 5_000_000) // 5ms
                    }
                } catch {
                    Issue.record("Task1 threw unexpected error: \(error)")
                }
            }
            
            let task2 = Task {
                do {
                    // Small delay to ensure task1 starts first and sets fatalErrorOnResolve = true
                    try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    
                    try await withTestContainer(unregisteredBehavior: .fatalError) {
                        factory2.register { "task2" }
                        // Task2 starts after task1, so it saves the wrong "original" value (true instead of false)
                        // Task2 runs longer to ensure task1 finishes first
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                    // When task2 finishes, it will restore fatalErrorOnResolve to true (wrong!)
                } catch {
                    Issue.record("Task2 threw unexpected error: \(error)")
                }
            }
            
            // Wait for both tasks to complete
            try await task1.value
            try await task2.value
            
            // Check if we hit the race condition
            let finalValue = Container.default.fatalErrorOnResolve
            if finalValue != false {
                Issue.record("Race condition detected! Final value is \(finalValue) but should be false. Task2 incorrectly restored the wrong 'original' value due to the race condition.")
                break // We proved the race condition exists, no need to continue
            }
        }
        #endif
    }
    #endif
    
    // IMPORTANT: These two tests (useProductionInterferesWithOtherTests_ThisTestShouldFail and
    // useProductionPersistsAcrossConcurrentTests_ThisTestShouldFail) are EXPECTED TO FAIL.
    // They demonstrate a design flaw where calling factory.useProduction() sets a global flag
    // on the factory instance that persists across test runs, causing test interference.
    //
    // The issue: Factory instances are typically defined as static properties, and useProduction()
    // modifies a global flag on that shared instance. Once set, ALL subsequent tests will bypass
    // their test containers and use production values instead of test-registered values.
    //
    // This is problematic because:
    // 1. Tests become order-dependent
    // 2. Concurrent tests can interfere with each other
    // 3. Test isolation is broken
    
    @Test func useProductionInterferesWithOtherTests_ThisTestShouldFail() async throws {
        // This test demonstrates the issue where useProduction() sets a global flag
        // that persists across tests, causing interference
        
        class ProductionService {
            let name: String
            init(name: String = "production") {
                self.name = name
            }
        }
        
        // Static factory that persists across test runs
        enum GlobalFactories {
            static let service = Factory { ProductionService() }
        }
        
        // PART 1: First "test" that uses production
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            // This simulates a test that decides to use production values
            // The problem is this sets a global flag on the factory!
            GlobalFactories.service.useProduction()
            
            let result = GlobalFactories.service()
            #expect(result.name == "production")
        }
        
        // PART 2: Second "test" that expects to use test registrations
        // This simulates a completely different test that runs after the first one
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Register a test-specific instance
            let testService = ProductionService(name: "test-instance")
            GlobalFactories.service.register { testService }
            
            // This SHOULD return our test instance, but because the previous
            // test called useProduction(), this factory is permanently in 
            // production mode and will ignore our registration!
            let result = GlobalFactories.service()
            
            // This expectation will FAIL, proving the interference
            #expect(result.name == "test-instance")
        }
    }
    
    @Test func useProductionPersistsAcrossConcurrentTests_ThisTestShouldFail() async throws {
        // This test shows the race condition when multiple tests run concurrently
        // and one uses production mode
        
        final class ConcurrentService: Sendable {
            let id: Int
            init(id: Int = 0) {
                self.id = id
            }
        }
        
        enum ConcurrentFactories {
            static let service = Factory { ConcurrentService() }
        }
        
        let testAStarted = DispatchSemaphore(value: 0)
        let testBCanProceed = DispatchSemaphore(value: 0)
        
        async let testA: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Test A uses production mode
            ConcurrentFactories.service.useProduction()
            testAStarted.signal()
            
            // Wait a bit to ensure Test B tries to use its registration
            _ = testBCanProceed.wait(timeout: .now() + 1)
            
            let result = ConcurrentFactories.service()
            #expect(result.id == 0, "Test A should get production instance")
        }
        
        async let testB: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Wait for Test A to set production mode
            _ = testAStarted.wait(timeout: .now() + 1)
            
            // Test B registers its own instance
            let testInstance = ConcurrentService(id: 999)
            ConcurrentFactories.service.register { testInstance }
            
            // This SHOULD return our registered instance (id: 999)
            // but will actually return production (id: 0) because
            // Test A has set the global production flag!
            let result = ConcurrentFactories.service()
            
            testBCanProceed.signal()
            
            #expect(result.id == 999)
        }
        
        _ = await (testA, testB)
    }
    
    @Test func testContainerHasOptionalDefaults() async throws {
        withTestContainer(defaults: .libraryDefaults) {
            #expect(Container.prodService() is NoopProdService) // does not crash
        }
    }
    
    @Test func testContainerHasComposableDefaults() async throws {
        withTestContainer(defaults: .myFeatureDefaults) {
            #expect(Container.prodService() is NoopProdService) // does not crash
        }
    }
}

// what a feature dev might write
extension TestDefaults {
    static let myFeatureDefaults = TestDefaults {
        .libraryDefaults // all defaults from the library
        prodServiceTestDefault // just this single one, this could be from anywhere
        TestDefault { Container.prodService.testValue { NoopProdService() } } // even if the library author didn't define it
    }
}

protocol ProdService { }

struct _ProdService: ProdService { }
struct NoopProdService: ProdService { }

extension Container {
    static let prodService = Factory { _ProdService() as ProdService }
}

// what a library author would do
extension TestDefaults {
    static let libraryDefaults = TestDefaults {
        prodServiceTestDefault
    }
    
    static let prodServiceTestDefault = TestDefault { Container.prodService.testValue { NoopProdService() } }
}
