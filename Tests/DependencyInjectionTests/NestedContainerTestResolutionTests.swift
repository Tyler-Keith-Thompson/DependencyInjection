//
//  NestedContainerTestResolutionTests.swift
//  DependencyInjection
//

import Testing
@testable import DependencyInjection

final class NestedModeDep: Sendable {
    let name: String
    init(_ name: String) { self.name = name }
}

/// `useProduction()` and `useParentContainer()` called from a `withNestedContainer`.
struct NestedContainerTestResolutionTests {
    nonisolated(unsafe) let failTestBehavior = UnregisteredBehavior.custom {
        Issue.record("Dependency for factory: \($0) not registered!")
    }

    @Test func doNothingInANestedContainerWithNoTestContainerAbove() async throws {
        let sync = Factory { NestedModeDep("production") }
        let syncThrowing = Factory { () throws -> NestedModeDep in NestedModeDep("production") }
        let async = Factory { @Sendable () async -> NestedModeDep in NestedModeDep("production") }
        let asyncThrowing = Factory { @Sendable () async throws -> NestedModeDep in NestedModeDep("production") }

        try await withNestedContainer {
            sync.register { NestedModeDep("nested") }
            syncThrowing.register { NestedModeDep("nested") }
            async.register { NestedModeDep("nested") }
            asyncThrowing.register { NestedModeDep("nested") }

            sync.useProduction().useParentContainer()
            syncThrowing.useProduction().useParentContainer()
            async.useProduction().useParentContainer()
            asyncThrowing.useProduction().useParentContainer()

            let a = sync().name
            let b = try syncThrowing().name
            let c = await async().name
            let d = try await asyncThrowing().name
            #expect([a, b, c, d] == ["nested", "nested", "nested", "nested"])
        }

        // Unregistered in the nested container: used to crash with "Factory not registered!".
        try await withNestedContainer {
            sync.useProduction()
            syncThrowing.useParentContainer()
            async.useProduction()
            asyncThrowing.useParentContainer()

            let a = sync().name
            let b = try syncThrowing().name
            let c = await async().name
            let d = try await asyncThrowing().name
            #expect([a, b, c, d] == ["production", "production", "production", "production"])
        }
    }

    @Test func useProductionFromANestedContainerSetsTheEnclosingTestContainer() async throws {
        let sync = Factory { NestedModeDep("production") }
        let syncThrowing = Factory { () throws -> NestedModeDep in NestedModeDep("production") }
        let async = Factory { @Sendable () async -> NestedModeDep in NestedModeDep("production") }
        let asyncThrowing = Factory { @Sendable () async throws -> NestedModeDep in NestedModeDep("production") }

        try await withTestContainer(unregisteredBehavior: failTestBehavior) {
            sync.register { NestedModeDep("test") }
            syncThrowing.register { NestedModeDep("test") }
            async.register { NestedModeDep("test") }
            asyncThrowing.register { NestedModeDep("test") }

            try await withNestedContainer {
                sync.useProduction()
                syncThrowing.useProduction()
                async.useProduction()
                asyncThrowing.useProduction()

                // A resolve in the nested container falls through to the test container.
                let a = sync().name
                let b = try syncThrowing().name
                let c = await async().name
                let d = try await asyncThrowing().name
                #expect([a, b, c, d] == ["production", "production", "production", "production"])
            }

            let a = sync().name
            let b = try syncThrowing().name
            let c = await async().name
            let d = try await asyncThrowing().name
            #expect([a, b, c, d] == ["production", "production", "production", "production"])
        }
    }

    @Test func useParentContainerFromANestedContainerSetsTheEnclosingTestContainer() {
        let factory = Factory { NestedModeDep("production") }
        withNestedContainer {
            factory.register { NestedModeDep("parent") }
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                withNestedContainer {
                    factory.useParentContainer()
                }
                #expect(factory().name == "parent")
            }
        }
    }

    @Test func concurrentTestContainersDoNotAffectEachOther() async {
        let factory = Factory { NestedModeDep("production") }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await withTestContainer(unregisteredBehavior: failTestBehavior) {
                        factory.register { NestedModeDep("test") }
                        if i.isMultiple(of: 2) {
                            withNestedContainer { factory.useProduction() }
                            await Task.yield()
                            #expect(factory().name == "production")
                        } else {
                            await Task.yield()
                            #expect(factory().name == "test")
                        }
                    }
                }
            }
        }
    }
}
