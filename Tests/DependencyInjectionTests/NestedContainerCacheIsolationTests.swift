//
//  NestedContainerCacheIsolationTests.swift
//  DependencyInjection
//

import Testing
@testable import DependencyInjection

final class IsolationDep: Sendable { }

/// A `withNestedContainer` inside `withTestContainer` reads caches up to the test container, never
/// above it.
struct NestedContainerCacheIsolationTests {
    nonisolated(unsafe) let failTestBehavior = UnregisteredBehavior.custom {
        Issue.record("Dependency for factory: \($0) not registered!")
    }

    @Test(arguments: [Scope.cached, Scope.shared])
    func nestedContainerInTestDoesNotReadAboveTheTestContainer_Sync(scope: Scope) {
        let factory = Factory(scope: scope) { IsolationDep() }
        withNestedContainer {
            let primed = factory()
            withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory.useProduction()
                withNestedContainer {
                    #expect(factory() !== primed)
                }
            }
            withExtendedLifetime(primed) { }
        }
    }

    @Test(arguments: [Scope.cached, Scope.shared])
    func nestedContainerInTestDoesNotReadAboveTheTestContainer_Async(scope: Scope) async {
        let factory = Factory(scope: scope) { @Sendable () async -> IsolationDep in IsolationDep() }
        await withNestedContainer {
            let primed = await factory()
            await withTestContainer(unregisteredBehavior: failTestBehavior) {
                factory.useProduction()
                await withNestedContainer {
                    #expect(await factory() !== primed)
                }
            }
            withExtendedLifetime(primed) { }
        }
    }

    @Test(arguments: [Scope.cached, Scope.shared])
    func nestedContainerInTestReadsTheTestContainersCache_Sync(scope: Scope) {
        let factory = Factory(scope: scope) { IsolationDep() }
        withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.useProduction()
            let inTest = factory()
            withNestedContainer {
                withNestedContainer {
                    #expect(factory() === inTest)
                }
            }
        }
    }

    @Test(arguments: [Scope.cached, Scope.shared])
    func nestedContainerInTestReadsTheTestContainersCache_Async(scope: Scope) async {
        let factory = Factory(scope: scope) { @Sendable () async -> IsolationDep in IsolationDep() }
        await withTestContainer(unregisteredBehavior: failTestBehavior) {
            factory.useProduction()
            let inTest = await factory()
            await withNestedContainer {
                #expect(await factory() === inTest)
            }
        }
    }

    @Test(arguments: [Scope.cached, Scope.shared])
    func parallelTestContainersNeverShareThroughNestedContainers(scope: Scope) async {
        let factory = Factory(scope: scope) { IsolationDep() }
        await withNestedContainer {
            let primed = factory()
            let instances = await withTaskGroup(of: IsolationDep.self) { group in
                for _ in 0..<50 {
                    group.addTask {
                        await withTestContainer(unregisteredBehavior: failTestBehavior) {
                            factory.useProduction()
                            await Task.yield()
                            return withNestedContainer { factory() }
                        }
                    }
                }
                return await group.reduce(into: [IsolationDep]()) { $0.append($1) }
            }
            let ids = Set(instances.map(ObjectIdentifier.init))
            #expect(ids.count == instances.count)
            #expect(!ids.contains(ObjectIdentifier(primed)))
        }
    }
}
