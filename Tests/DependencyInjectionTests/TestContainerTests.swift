//
//  TestContainerTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Testing
import Dispatch
import Foundation
import DependencyInjection

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
    #endif
}
