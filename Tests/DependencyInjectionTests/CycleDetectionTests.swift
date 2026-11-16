//
//  CycleDetectionTests.swift
//  DependencyInjection
//

import Testing
import Foundation
@testable import DependencyInjection

// Sync cycle through constructor injection: CycleA -> CycleB -> CycleA.
final class CycleA {
    @ConstructorInjected(Container.cycleB) var b: CycleB
}
final class CycleB {
    @ConstructorInjected(Container.cycleA) var a: CycleA
}

// Async cycle through a cached scope, which would otherwise wait on itself forever.
final class AsyncCycleA: Sendable {
    init() async { _ = await Container.asyncCycleB() }
}
final class AsyncCycleB: Sendable {
    init() async { _ = await Container.asyncCycleA() }
}

// Diamond: Top -> Left -> Bottom, Top -> Right -> Bottom. Not a cycle.
final class DiamondBottom { }
final class DiamondLeft { @ConstructorInjected(Container.diamondBottom) var bottom: DiamondBottom }
final class DiamondRight { @ConstructorInjected(Container.diamondBottom) var bottom: DiamondBottom }
final class DiamondTop {
    @ConstructorInjected(Container.diamondLeft) var left: DiamondLeft
    @ConstructorInjected(Container.diamondRight) var right: DiamondRight
}

final class SelfReferencing { }

// Back-references resolved from a task the owner starts but never waits on. Not cycles: by the
// time the task resolves the owner again, it comes from the cache (or waits for it to finish).
final class BackRefOwner: Sendable {
    let child: Task<BackRefChild, Never>
    init() { child = Task { await Container.backRefChild() } }
}
final class BackRefChild: Sendable {
    let owner: BackRefOwner
    init() { owner = Container.backRefOwner() }
}
final class AsyncBackRefOwner: Sendable {
    let child: Task<AsyncBackRefChild, Never>
    init() async { child = Task { await Container.asyncBackRefChild() } }
}
final class AsyncBackRefChild: Sendable {
    let owner: AsyncBackRefOwner
    init() async { owner = await Container.asyncBackRefOwner() }
}

extension Container {
    // Explicit types: inferring them would make the compiler expand the two classes' macros in a loop.
    static let cycleA: SyncFactory<CycleA> = Factory { CycleA() }
    static let cycleB: SyncFactory<CycleB> = Factory { CycleB() }
    static let asyncCycleA = Factory(scope: .cached) { @Sendable () async -> AsyncCycleA in await AsyncCycleA() }
    static let asyncCycleB = Factory(scope: .cached) { @Sendable () async -> AsyncCycleB in await AsyncCycleB() }
    static let selfReferencing = Factory { SelfReferencing() }
    static let backRefOwner: SyncFactory<BackRefOwner> = Factory(scope: .cached) { BackRefOwner() }
    static let backRefChild: AsyncFactory<BackRefChild> = Factory { @Sendable () async -> BackRefChild in BackRefChild() }
    static let asyncBackRefOwner: AsyncFactory<AsyncBackRefOwner> = Factory(scope: .cached) { @Sendable () async -> AsyncBackRefOwner in await AsyncBackRefOwner() }
    static let asyncBackRefChild: AsyncFactory<AsyncBackRefChild> = Factory { @Sendable () async -> AsyncBackRefChild in await AsyncBackRefChild() }
    static let diamondBottom: SyncFactory<DiamondBottom> = Factory { DiamondBottom() }
    static let diamondLeft: SyncFactory<DiamondLeft> = Factory { DiamondLeft() }
    static let diamondRight: SyncFactory<DiamondRight> = Factory { DiamondRight() }
    static let diamondTop: SyncFactory<DiamondTop> = Factory { DiamondTop() }
}

struct CycleDetectionTests {
    @Test func syncCycleThroughConstructorInjectionStopsWithTheCycle() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            _ = Container.cycleA()
        }
        let stderr = String(decoding: try #require(result).standardErrorContent, as: UTF8.self)
        #expect(stderr.contains("Dependency cycle detected: CycleA depends on itself."))
        #expect(stderr.contains("  CycleA  (resolved at CycleDetectionTests.swift:"))
        #expect(stderr.contains("  → CycleB  (resolved at CycleDetectionTests.swift:12"))
        #expect(stderr.contains("  → CycleA  (resolved at CycleDetectionTests.swift:15"))
    }

    @Test func registrationThatResolvesItsOwnFactoryStops() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            withTestContainer {
                Container.selfReferencing.register { Container.selfReferencing() }
                _ = Container.selfReferencing()
            }
        }
        let stderr = String(decoding: try #require(result).standardErrorContent, as: UTF8.self)
        #expect(stderr.contains("Dependency cycle detected: SelfReferencing depends on itself."))
    }

    @Test func asyncCachedCycleStopsInsteadOfHanging() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            _ = await Container.asyncCycleA()
        }
        let stderr = String(decoding: try #require(result).standardErrorContent, as: UTF8.self)
        #expect(stderr.contains("Dependency cycle detected: AsyncCycleA depends on itself."))
        #expect(stderr.contains("  → AsyncCycleB  (resolved at CycleDetectionTests.swift:"))
    }

    // These resolve real factories, so they run in a test container: resolving against the
    // default container while another test is inside one is a guarded error.
    private func withDiamondInProduction<T>(_ body: () async throws -> T) async rethrows -> T {
        try await withTestContainer {
            Container.diamondBottom.useProduction()
            Container.diamondLeft.useProduction()
            Container.diamondRight.useProduction()
            Container.diamondTop.useProduction()
            return try await body()
        }
    }

    @Test func diamondIsNotACycle() async {
        await withDiamondInProduction {
            let top = Container.diamondTop()
            #expect(top.left.bottom !== top.right.bottom)
        }
    }

    @Test func resolvingTheSameFactoryRepeatedlyIsNotACycle() async {
        await withDiamondInProduction {
            #expect(Container.diamondBottom() !== Container.diamondBottom())
        }
    }

    @Test func concurrentResolutionsOfTheSameFactoryAreNotACycle() async {
        await withDiamondInProduction {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<50 {
                    group.addTask { _ = Container.diamondTop() }
                }
            }
        }
    }

    @Test func pathIsEmptyOutsideResolution() async {
        await withDiamondInProduction {
            _ = Container.diamondTop()
            #expect(CycleDetection.path == nil)
        }
    }

    @Test func backReferenceFromATaskTheOwnerDoesNotAwaitIsNotACycle() async {
        await withTestContainer {
            Container.backRefOwner.useProduction()
            Container.backRefChild.useProduction()
            let owner = Container.backRefOwner()
            let child = await owner.child.value
            #expect(child.owner === owner)
        }
    }

    @Test func asyncBackReferenceFromATaskTheOwnerDoesNotAwaitIsNotACycle() async {
        await withTestContainer {
            Container.asyncBackRefOwner.useProduction()
            Container.asyncBackRefChild.useProduction()
            let owner = await Container.asyncBackRefOwner()
            let child = await owner.child.value
            #expect(child.owner === owner)
        }
    }
}
