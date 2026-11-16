//
//  UseParentContainerTests.swift
//  DependencyInjection
//

import Testing
@testable import DependencyInjection

final class ParentContainerDep: Sendable {
    let name: String
    init(_ name: String) { self.name = name }
}

struct UseParentContainerTests {
    nonisolated(unsafe) let failTestBehavior = UnregisteredBehavior.custom {
        Issue.record("Dependency for factory: \($0) not registered!")
    }

    @Test func usesRegistrationFromEnclosingNestedContainer() {
        let factory = Factory { ParentContainerDep("production") }
        withNestedContainer {
            factory.register { ParentContainerDep("parent") }
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory.useParentContainer()
                #expect(factory().name == "parent")
            }
        }
    }

    @Test func fallsBackToProductionWhenNothingAboveIsRegistered() {
        let factory = Factory { ParentContainerDep("production") }
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.useParentContainer()
            #expect(factory().name == "production")
        }
    }

    @Test func takesPrecedenceOverTestContainerRegistration() {
        let factory = Factory { ParentContainerDep("production") }
        withNestedContainer {
            factory.register { ParentContainerDep("parent") }
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory.register { ParentContainerDep("test") }
                factory.useParentContainer()
                #expect(factory().name == "parent")
            }
        }
    }

    @Test func respectsScopeWithoutCachingIntoTheParent() {
        let factory = Factory(scope: .cached) { ParentContainerDep("production") }
        withNestedContainer {
            factory.register { ParentContainerDep("parent") }
            let inTest = withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory.useParentContainer()
                let first = factory()
                #expect(factory() === first)
                return first
            }
            #expect(factory() !== inTest)
        }
    }

    @Test func mostRecentOfUseProductionAndUseParentContainerWins() {
        let factory = Factory { ParentContainerDep("production") }
        withNestedContainer {
            factory.register { ParentContainerDep("parent") }
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory.useParentContainer().useProduction()
                #expect(factory().name == "production")
                factory.useParentContainer()
                #expect(factory().name == "parent")
            }
        }
    }

    @Test func doesNotAffectOtherTestContainers() {
        let factory = Factory { ParentContainerDep("production") }
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.useParentContainer()
            #expect(factory().name == "production")
        }
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.register { ParentContainerDep("test") }
            #expect(factory().name == "test")
        }
    }

    @Test func worksForEveryFactoryKind() async throws {
        let syncThrowing = Factory { () throws -> ParentContainerDep in ParentContainerDep("production") }
        let async = Factory { @Sendable () async -> ParentContainerDep in ParentContainerDep("production") }
        let asyncThrowing = Factory { @Sendable () async throws -> ParentContainerDep in ParentContainerDep("production") }

        try await withNestedContainer {
            syncThrowing.register { ParentContainerDep("parent") }
            async.register { ParentContainerDep("parent") }
            asyncThrowing.register { ParentContainerDep("parent") }
            try await withTestContainer(unregisteredBehavior: failTestBehavior) {
                syncThrowing.useParentContainer()
                async.useParentContainer()
                asyncThrowing.useParentContainer()
                let a = try syncThrowing().name
                let b = await async().name
                let c = try await asyncThrowing().name
                #expect([a, b, c] == ["parent", "parent", "parent"])
            }
        }
    }
}
