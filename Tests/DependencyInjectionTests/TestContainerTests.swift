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
    
    @Test func asyncThrowingCachedFactory_TaskStorageInterference() async throws {
        // This test demonstrates the bug where taskStorage isn't cleared when a factory is re-registered
        // Specifically for async throwing factories which might be the issue in the real project
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let cachedAsyncThrowingFactory = Factory(scope: .cached) { () async throws -> MyService in
                // Add delay to simulate async work
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return MyService(id: "default")
            }
        }
        
        // First test container - establish a cached value
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service1 = MyService(id: "test1")
            Globals.cachedAsyncThrowingFactory.register { service1 }
            let resolved1 = try await Globals.cachedAsyncThrowingFactory()
            #expect(resolved1.id == "test1")
        }
        
        // Second test container - this should work independently  
        // But if taskStorage isn't cleared, it might return the wrong value
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service2 = MyService(id: "test2")
            Globals.cachedAsyncThrowingFactory.register { service2 }
            
            // This might fail if taskStorage from the first container is still there
            let resolved2 = try await Globals.cachedAsyncThrowingFactory()
            #expect(resolved2.id == "test2", "Second container should get its own registered value, not test1")
        }
    }
    
    @Test func asyncThrowingCachedFactory_ConcurrentInterference() async throws {
        // Test concurrent interference with async throwing factories
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let cachedAsyncThrowingFactory = Factory(scope: .cached) { () async throws -> MyService in
                // Add delay to ensure concurrent access
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                return MyService(id: "default")
            }
        }
        
        // Use continuations for coordination
        let (aReadyStream, aReadyContinuation) = AsyncStream.makeStream(of: Void.self)
        let (bDoneStream, bDoneContinuation) = AsyncStream.makeStream(of: Void.self)
        
        async let a: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            let serviceA = MyService(id: "testA")
            Globals.cachedAsyncThrowingFactory.register { serviceA }
            aReadyContinuation.yield(())
            
            // First resolution in container A
            let firstA = try await Globals.cachedAsyncThrowingFactory()
            #expect(firstA.id == "testA")
            
            // Wait for B to register and resolve
            for await _ in bDoneStream { break }
            
            // This should still return testA because we're in container A
            // But if the cache/taskStorage is shared, it might return testB
            let secondA = try await Globals.cachedAsyncThrowingFactory()
            #expect(secondA.id == "testA", "Container A should maintain its own cached value")
        }
        
        async let b: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Wait for A to start
            for await _ in aReadyStream { break }
            
            let serviceB = MyService(id: "testB")
            Globals.cachedAsyncThrowingFactory.register { serviceB }
            
            // This should return testB, not be affected by container A
            let resolvedB = try await Globals.cachedAsyncThrowingFactory()
            #expect(resolvedB.id == "testB", "Container B should get its own registered value")
            
            bDoneContinuation.yield(())
        }
        
        _ = try await (a, b)
    }
    
    @Test func asyncCachedFactory_ReregistrationDuringResolve() async throws {
        // This test demonstrates that re-registering a factory while a resolution is in progress
        // should not affect new resolutions
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let cachedAsyncFactory = Factory(scope: .cached) { () async -> MyService in
                // Significant delay to ensure we can re-register while this is running
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                return MyService(id: "default")
            }
        }
        
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service1 = MyService(id: "test1")
            Globals.cachedAsyncFactory.register { 
                // Delay here too to make the race condition more likely
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                return service1
            }
            
            // Start multiple concurrent resolutions
            async let resolution1 = Globals.cachedAsyncFactory()
            
            // Wait a bit for resolution1 to start
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            
            // Re-register while resolution1 is still in progress
            let service2 = MyService(id: "test2")
            Globals.cachedAsyncFactory.register { service2 }
            
            // Start a new resolution after re-registration
            async let resolution2 = Globals.cachedAsyncFactory()
            
            // Collect results
            let result1 = await resolution1
            let result2 = await resolution2
            
            // resolution1 should get test1 (it was already in flight)
            #expect(result1.id == "test1", "First resolution started before re-registration should get original value")
            
            // resolution2 should get test2 (it started after re-registration)
            #expect(result2.id == "test2", "Second resolution started after re-registration should get new value")
        }
    }
    
    @Test func asyncCachedFactory_ConcurrentTaskStorageInterference() async throws {
        // This test shows concurrent test container interference with async cached factories
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            nonisolated(unsafe) static let cachedAsyncFactory = Factory(scope: .cached) { () async -> MyService in
                // Add delay to ensure tasks overlap
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                return MyService(id: "default")
            }
        }
        
        // Use continuations for coordination
        let (aReadyStream, aReadyContinuation) = AsyncStream.makeStream(of: Void.self)
        let (bReadyStream, bReadyContinuation) = AsyncStream.makeStream(of: Void.self)
        let (aResolvedStream, aResolvedContinuation) = AsyncStream.makeStream(of: Void.self)
        
        async let a: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            let serviceA = MyService(id: "testA")
            Globals.cachedAsyncFactory.register { serviceA }
            aReadyContinuation.yield(())
            
            // Start resolving the factory - this will create a Task in taskStorage
            let firstA = await Globals.cachedAsyncFactory()
            #expect(firstA.id == "testA")
            aResolvedContinuation.yield(())
            
            // Wait for B to register its own resolver
            for await _ in bReadyStream { break }
            
            // This should still return testA because we're in container A
            // But if taskStorage isn't properly isolated, it might return testB
            let secondA = await Globals.cachedAsyncFactory()
            #expect(secondA.id == "testA", "Container A should maintain its own cached value")
        }
        
        async let b: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Wait for A to register and start resolving
            for await _ in aReadyStream { break }
            for await _ in aResolvedStream { break }
            
            let serviceB = MyService(id: "testB")
            Globals.cachedAsyncFactory.register { serviceB }
            bReadyContinuation.yield(())
            
            // This should return testB, not be affected by container A's task
            let resolvedB = await Globals.cachedAsyncFactory()
            #expect(resolvedB.id == "testB", "Container B should get its own registered value")
        }
        
        _ = await (a, b)
    }

    @Test func uniqueScopeInterferenceAcrossTestContainers() async throws {
        // Test that unique scopes don't have interference between test containers
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let uniqueFactory = Factory(scope: .unique) { MyService(id: "default") }
        }
        
        // First test container
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service1 = MyService(id: "test1")
            Globals.uniqueFactory.register { service1 }
            let resolved1 = Globals.uniqueFactory()
            #expect(resolved1.id == "test1")
        }
        
        // Second test container - should work independently
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service2 = MyService(id: "test2")
            Globals.uniqueFactory.register { service2 }
            let resolved2 = Globals.uniqueFactory()
            #expect(resolved2.id == "test2", "Second container should get its own registered value")
        }
    }
    
    @Test func uniqueScopeAsyncInterferenceAcrossTestContainers() async throws {
        // Test async unique scope factories across test containers
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let uniqueAsyncFactory = Factory(scope: .unique) { () async -> MyService in
                // Add delay to simulate async work
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return MyService(id: "default")
            }
        }
        
        // First test container
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service1 = MyService(id: "test1")
            Globals.uniqueAsyncFactory.register { service1 }
            let resolved1 = await Globals.uniqueAsyncFactory()
            #expect(resolved1.id == "test1")
        }
        
        // Second test container - should work independently
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service2 = MyService(id: "test2")
            Globals.uniqueAsyncFactory.register { service2 }
            let resolved2 = await Globals.uniqueAsyncFactory()
            #expect(resolved2.id == "test2", "Second container should get its own registered value")
        }
    }
    
    @Test func uniqueScopeConcurrentInterference() async throws {
        // Test concurrent test containers with unique scope
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let uniqueFactory = Factory(scope: .unique) { MyService(id: "default") }
        }
        
        // Use continuations for coordination
        let (aReadyStream, aReadyContinuation) = AsyncStream.makeStream(of: Void.self)
        let (bDoneStream, bDoneContinuation) = AsyncStream.makeStream(of: Void.self)
        
        async let a: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            let serviceA = MyService(id: "testA")
            Globals.uniqueFactory.register { serviceA }
            aReadyContinuation.yield(())
            
            // First resolution in container A
            let firstA = Globals.uniqueFactory()
            #expect(firstA.id == "testA")
            
            // Wait for B to register and resolve
            for await _ in bDoneStream { break }
            
            // This should still return a new instance with testA
            let secondA = Globals.uniqueFactory()
            #expect(secondA.id == "testA", "Container A should maintain its own registered resolver")
        }
        
        async let b: Void = withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Wait for A to start
            for await _ in aReadyStream { break }
            
            let serviceB = MyService(id: "testB")
            Globals.uniqueFactory.register { serviceB }
            
            // This should return testB, not be affected by container A
            let resolvedB = Globals.uniqueFactory()
            #expect(resolvedB.id == "testB", "Container B should get its own registered value")
            
            bDoneContinuation.yield(())
        }
        
        _ = await (a, b)
    }

    @Test func uniqueScopeThrowingInterferenceAcrossTestContainers() async throws {
        // Test throwing unique scope factories across test containers
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let uniqueThrowingFactory = Factory(scope: .unique) { () throws -> MyService in
                MyService(id: "default")
            }
        }
        
        // First test container
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service1 = MyService(id: "test1")
            Globals.uniqueThrowingFactory.register { service1 }
            let resolved1 = try Globals.uniqueThrowingFactory()
            #expect(resolved1.id == "test1")
        }
        
        // Second test container - should work independently
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service2 = MyService(id: "test2")
            Globals.uniqueThrowingFactory.register { service2 }
            let resolved2 = try Globals.uniqueThrowingFactory()
            #expect(resolved2.id == "test2", "Second container should get its own registered value")
        }
    }

    @Test func uniqueScopeAsyncThrowingInterferenceAcrossTestContainers() async throws {
        // Test async throwing unique scope factories across test containers
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let uniqueAsyncThrowingFactory = Factory(scope: .unique) { () async throws -> MyService in
                // Add delay to simulate async work
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return MyService(id: "default")
            }
        }
        
        // First test container
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service1 = MyService(id: "test1")
            Globals.uniqueAsyncThrowingFactory.register { service1 }
            let resolved1 = try await Globals.uniqueAsyncThrowingFactory()
            #expect(resolved1.id == "test1")
        }
        
        // Second test container - should work independently
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let service2 = MyService(id: "test2")
            Globals.uniqueAsyncThrowingFactory.register { service2 }
            let resolved2 = try await Globals.uniqueAsyncThrowingFactory()
            #expect(resolved2.id == "test2", "Second container should get its own registered value")
        }
    }

    @Test func multipleTestContainersWithRegistrations_NoInterference() async throws {
        // This test simulates multiple tests running sequentially, each with their own registrations
        // to check if registrations somehow leak between test containers
        
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        final class MyDependency: Sendable {
            let name: String
            init(name: String) { self.name = name }
        }
        
        enum Globals {
            // Various scopes to test
            static let uniqueService = Factory(scope: .unique) { MyService(id: "default-unique") }
            static let cachedService = Factory(scope: .cached) { MyService(id: "default-cached") }
            static let sharedService = Factory(scope: .shared) { MyService(id: "default-shared") }
            
            // A factory that depends on another factory
            static let dependentService = Factory(scope: .unique) { 
                MyDependency(name: "uses-\(uniqueService().id)")
            }
        }
        
        // Test 1: Register with specific values
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            Globals.uniqueService.register { MyService(id: "test1-unique") }
            Globals.cachedService.register { MyService(id: "test1-cached") }
            Globals.sharedService.register { MyService(id: "test1-shared") }
            Globals.dependentService.register { MyDependency(name: "test1-dependent") }
            
            let unique = Globals.uniqueService()
            let cached = Globals.cachedService()
            let shared = Globals.sharedService()
            let dependent = Globals.dependentService()
            
            #expect(unique.id == "test1-unique")
            #expect(cached.id == "test1-cached")
            #expect(shared.id == "test1-shared")
            #expect(dependent.name == "test1-dependent")
        }
        
        // Test 2: Different registrations - should NOT see test1 values
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Only register some factories, not all
            Globals.uniqueService.register { MyService(id: "test2-unique") }
            Globals.cachedService.register { MyService(id: "test2-cached") }
            // Note: NOT registering sharedService or dependentService
            
            let unique = Globals.uniqueService()
            let cached = Globals.cachedService()
            
            #expect(unique.id == "test2-unique", "Should get test2 value, not test1")
            #expect(cached.id == "test2-cached", "Should get test2 value, not test1")
            
            // These should get production values with custom behavior
            let shared = Globals.sharedService()
            let dependent = Globals.dependentService()
            #expect(shared.id == "default-shared")
            #expect(dependent.name == "uses-test2-unique")
        }
        
        // Test 3: No registrations - get production values with custom behavior
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            // Don't register anything
            
            let unique = Globals.uniqueService()
            let cached = Globals.cachedService()
            let shared = Globals.sharedService()
            let dependent = Globals.dependentService()
            #expect(unique.id == "default-unique")
            #expect(cached.id == "default-cached")
            #expect(shared.id == "default-shared")
            #expect(dependent.name == "uses-default-unique")
        }
        
        // Test 4: Register again with new values - should work independently
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            Globals.uniqueService.register { MyService(id: "test4-unique") }
            Globals.cachedService.register { MyService(id: "test4-cached") }
            Globals.sharedService.register { MyService(id: "test4-shared") }
            Globals.dependentService.register { MyDependency(name: "test4-dependent") }
            
            let unique = Globals.uniqueService()
            let cached = Globals.cachedService()
            let shared = Globals.sharedService()
            let dependent = Globals.dependentService()
            
            #expect(unique.id == "test4-unique", "Should not see values from test1 or test2")
            #expect(cached.id == "test4-cached", "Should not see values from test1 or test2")
            #expect(shared.id == "test4-shared", "Should not see values from test1")
            #expect(dependent.name == "test4-dependent", "Should not see values from test1")
        }
    }
    
    @Test func registrationLeakageAcrossTestContainers_Production() async throws {
        // Test if registrations leak when resolving production values
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let service = Factory(scope: .unique) { MyService(id: "production") }
        }
        
        // First, resolve the production value (in a test container with no registration - gets production value)
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let prodValue = Globals.service()
            #expect(prodValue.id == "production")
        }
        
        // Now use test container with registration
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            Globals.service.register { MyService(id: "test-value") }
            let testValue = Globals.service()
            #expect(testValue.id == "test-value")
        }
        
        // After test container, should get production value again
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let prodValueAgain = Globals.service()
            #expect(prodValueAgain.id == "production", "Should be back to production value after test container")
        }
        
        // Another test container with different registration
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            Globals.service.register { MyService(id: "another-test-value") }
            let testValue = Globals.service()
            #expect(testValue.id == "another-test-value", "Should get the newly registered value")
        }
        
        // Should still be production after second test container
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            let finalProdValue = Globals.service()
            #expect(finalProdValue.id == "production", "Should still be production value")
        }
    }

    @Test func parallelTestContainers_RegistrationInterference() async throws {
        // This test simulates multiple tests running IN PARALLEL, each with their own registrations
        // This is the real-world scenario where test interference is most likely
        
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let uniqueService = Factory(scope: .unique) { MyService(id: "production-unique") }
            static let cachedService = Factory(scope: .cached) { MyService(id: "production-cached") }
            static let sharedService = Factory(scope: .shared) { MyService(id: "production-shared") }
        }
        
        // Run multiple test containers in parallel
        await withTaskGroup(of: Void.self) { group in
            // Test A
            group.addTask {
                await withTestContainer(unregisteredBehavior: self.failTestBehavior) {
                    Globals.uniqueService.register { MyService(id: "testA-unique") }
                    Globals.cachedService.register { MyService(id: "testA-cached") }
                    Globals.sharedService.register { MyService(id: "testA-shared") }
                    
                    // Add some delay to ensure overlap
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    
                    let unique = Globals.uniqueService()
                    let cached = Globals.cachedService()
                    let shared = Globals.sharedService()
                    
                    #expect(unique.id == "testA-unique", "Test A should see its own registered values")
                    #expect(cached.id == "testA-cached", "Test A should see its own registered values")
                    #expect(shared.id == "testA-shared", "Test A should see its own registered values")
                    
                    // Resolve multiple times to check consistency
                    for _ in 0..<5 {
                        let u = Globals.uniqueService()
                        let c = Globals.cachedService()
                        let s = Globals.sharedService()
                        #expect(u.id == "testA-unique", "Should consistently get testA values")
                        #expect(c.id == "testA-cached", "Should consistently get testA values")
                        #expect(s.id == "testA-shared", "Should consistently get testA values")
                        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    }
                }
            }
            
            // Test B
            group.addTask {
                await withTestContainer(unregisteredBehavior: self.failTestBehavior) {
                    Globals.uniqueService.register { MyService(id: "testB-unique") }
                    Globals.cachedService.register { MyService(id: "testB-cached") }
                    Globals.sharedService.register { MyService(id: "testB-shared") }
                    
                    // Add some delay to ensure overlap
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    
                    let unique = Globals.uniqueService()
                    let cached = Globals.cachedService()
                    let shared = Globals.sharedService()
                    
                    #expect(unique.id == "testB-unique", "Test B should see its own registered values")
                    #expect(cached.id == "testB-cached", "Test B should see its own registered values")
                    #expect(shared.id == "testB-shared", "Test B should see its own registered values")
                    
                    // Resolve multiple times to check consistency
                    for _ in 0..<5 {
                        let u = Globals.uniqueService()
                        let c = Globals.cachedService()
                        let s = Globals.sharedService()
                        #expect(u.id == "testB-unique", "Should consistently get testB values")
                        #expect(c.id == "testB-cached", "Should consistently get testB values")
                        #expect(s.id == "testB-shared", "Should consistently get testB values")
                        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    }
                }
            }
            
            // Test C
            group.addTask {
                await withTestContainer(unregisteredBehavior: self.failTestBehavior) {
                    Globals.uniqueService.register { MyService(id: "testC-unique") }
                    Globals.cachedService.register { MyService(id: "testC-cached") }
                    Globals.sharedService.register { MyService(id: "testC-shared") }
                    
                    // Add some delay to ensure overlap
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    
                    let unique = Globals.uniqueService()
                    let cached = Globals.cachedService()
                    let shared = Globals.sharedService()
                    
                    #expect(unique.id == "testC-unique", "Test C should see its own registered values")
                    #expect(cached.id == "testC-cached", "Test C should see its own registered values")
                    #expect(shared.id == "testC-shared", "Test C should see its own registered values")
                    
                    // Resolve multiple times to check consistency
                    for _ in 0..<5 {
                        let u = Globals.uniqueService()
                        let c = Globals.cachedService()
                        let s = Globals.sharedService()
                        #expect(u.id == "testC-unique", "Should consistently get testC values")
                        #expect(c.id == "testC-cached", "Should consistently get testC values")
                        #expect(s.id == "testC-shared", "Should consistently get testC values")
                        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    }
                }
            }
        }
        
        // After all parallel tests, should be back to production values
        let finalUnique = Globals.uniqueService()
        let finalCached = Globals.cachedService()
        let finalShared = Globals.sharedService()
        #expect(finalUnique.id == "production-unique", "Should be back to production after test containers")
        #expect(finalCached.id == "production-cached", "Should be back to production after test containers")
        #expect(finalShared.id == "production-shared", "Should be back to production after test containers")
    }
    
    @Test func parallelTestContainers_MixedRegistrations() async throws {
        // Test where different parallel tests register different subsets of factories
        final class MyService: Sendable {
            let id: String
            init(id: String) { self.id = id }
        }
        
        enum Globals {
            static let service1 = Factory(scope: .unique) { MyService(id: "prod-1") }
            static let service2 = Factory(scope: .cached) { MyService(id: "prod-2") }
            static let service3 = Factory(scope: .shared) { MyService(id: "prod-3") }
        }
        
        await withTaskGroup(of: Void.self) { group in
            // Test that only registers service1
            group.addTask {
                await withTestContainer(unregisteredBehavior: self.failTestBehavior) {
                    Globals.service1.register { MyService(id: "testA-service1") }
                    // NOT registering service2 or service3
                    
                    for _ in 0..<10 {
                        let s1 = Globals.service1()
                        #expect(s1.id == "testA-service1")
                        
                        // These should get production values with custom behavior
                        // since custom behavior doesn't stop execution
                        let s2 = Globals.service2()
                        let s3 = Globals.service3()
                        #expect(s2.id == "prod-2", "Should get production value for unregistered factory")
                        #expect(s3.id == "prod-3", "Should get production value for unregistered factory")
                        try? await Task.sleep(nanoseconds: 500_000) // 0.5ms
                    }
                }
            }
            
            // Test that only registers service2
            group.addTask {
                await withTestContainer(unregisteredBehavior: self.failTestBehavior) {
                    Globals.service2.register { MyService(id: "testB-service2") }
                    // NOT registering service1 or service3
                    
                    for _ in 0..<10 {
                        let s2 = Globals.service2()
                        #expect(s2.id == "testB-service2")
                        
                        // These should get production values with custom behavior
                        // since custom behavior doesn't stop execution
                        let s1 = Globals.service1()
                        let s3 = Globals.service3()
                        #expect(s1.id == "prod-1", "Should get production value for unregistered factory")
                        #expect(s3.id == "prod-3", "Should get production value for unregistered factory")
                        try? await Task.sleep(nanoseconds: 500_000) // 0.5ms
                    }
                }
            }
            
            // Test that registers all services
            group.addTask {
                await withTestContainer(unregisteredBehavior: self.failTestBehavior) {
                    Globals.service1.register { MyService(id: "testC-service1") }
                    Globals.service2.register { MyService(id: "testC-service2") }
                    Globals.service3.register { MyService(id: "testC-service3") }
                    
                    for _ in 0..<10 {
                        let s1 = Globals.service1()
                        let s2 = Globals.service2()
                        let s3 = Globals.service3()
                        #expect(s1.id == "testC-service1")
                        #expect(s2.id == "testC-service2")
                        #expect(s3.id == "testC-service3")
                        try? await Task.sleep(nanoseconds: 500_000) // 0.5ms
                    }
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
}
