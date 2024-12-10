//
//  TestContainerTests.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

import Testing
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
}
