//
//  TestContainerTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Testing
import Dispatch
import DependencyInjection

struct TestContainerTests {
    let failTestBehavior = UnregisteredBehavior.custom {
        Issue.record("Dependency for factory: \($0) not registered!")
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
