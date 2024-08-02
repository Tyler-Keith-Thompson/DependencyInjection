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
        
        withKnownIssue {
            _ = withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory()
            }
        }
    }
    
    @Test func synchronousThrowingFactoryCanResolveAUniqueType() async throws {
        class Super {
            init() throws { }
        }
        let factory = Factory { try Super() }
        
        withKnownIssue {
            _ = try withTestContainer(unregisteredBehavior: failTestBehavior) {
                try factory()
            }
        }
    }
    
    @Test func asynchronousFactoryCanResolveAUniqueType() async throws {
        actor Super {
            init() async { }
        }
        let factory = Factory { await Super() }
        
        await withKnownIssue {
            _ = await withTestContainer(unregisteredBehavior: failTestBehavior) {
                await factory()
            }
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveAUniqueType() async throws {
        actor Super {
            init() async throws { }
        }
        let factory = Factory { try await Super() }
        
        await withKnownIssue {
            _ = try await withTestContainer(unregisteredBehavior: failTestBehavior) {
                try await factory()
            }
        }
    }
}
