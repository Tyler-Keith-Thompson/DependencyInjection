//
//  TestContainerTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Testing
import Foundation
import DependencyInjection

struct TestContainerTests {
    let failTestBehavior = UnregisteredBehavior.custom {
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

        // Prime cache outside test container
        _ = Globals.cachedDep()

        withTestContainer(unregisteredBehavior: failTestBehavior) {
            let testValue = MyDep()
            Globals.cachedDep.register { testValue }
            #expect(Globals.cachedDep() === testValue)
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
    @Test func synchronousFactoryCanResolveAUniqueType() async throws {
        class Super { }
        let factory = Factory { Super() }
        let val = Super()
        factory.register { val }
        
        withKnownIssue {
            _ = withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory()
            }
        }
        
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.popRegistration()
            let resolved = factory()
            #expect(resolved === val)
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
    
    @Test func synchronousThrowingFactoryCanResolveAUniqueType() async throws {
        class Super {
            init() throws { }
        }
        let factory = Factory { try Super() }
        let val = try Super()
        factory.register { val }
        
        withKnownIssue {
            _ = try withTestContainer(unregisteredBehavior: failTestBehavior) {
                try factory()
            }
        }
        
        try withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.popRegistration()
            let resolved = try factory()
            #expect(resolved === val)
        }
    }
    
    @Test func asynchronousFactoryCanResolveAUniqueType() async throws {
        actor Super {
            init() async { }
        }
        let factory = Factory { await Super() }
        let val = await Super()
        factory.register { val }

        await withKnownIssue {
            _ = await withTestContainer(unregisteredBehavior: failTestBehavior) {
                await factory()
            }
        }
        
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.popRegistration()
            let resolved = await factory()
            #expect(resolved === val)
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveAUniqueType() async throws {
        actor Super {
            init() async throws { }
        }
        let factory = Factory { try await Super() }
        let val = try await Super()
        factory.register { val }

        await withKnownIssue {
            _ = try await withTestContainer(unregisteredBehavior: failTestBehavior) {
                try await factory()
            }
        }
        
        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.popRegistration()
            let resolved = try await factory()
            #expect(resolved === val)
        }
    }
}
