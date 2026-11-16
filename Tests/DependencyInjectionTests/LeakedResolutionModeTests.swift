//
//  LeakedResolutionModeTests.swift
//  DependencyInjection
//

import Foundation
import Testing
@testable import DependencyInjection

final class LeakModeDep: Sendable {
    let name: String
    init(_ name: String) { self.name = name }
}

/// Records each leak and answers with a "leaked" value, so a test can tell a leak from a resolve.
final class RecordingLeakBehavior: LeakedResolutionBehavior, @unchecked Sendable {
    private let lock = NSLock()
    private var _leaks = 0
    var leaks: Int { lock.withLock { _leaks } }

    private func record<D>() -> LeakedResolutionStrategy<D> {
        lock.withLock { _leaks += 1 }
        return .returnValue(LeakModeDep("leaked") as! D)
    }

    func onLeak<D>(factory: SyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) -> LeakedResolutionStrategy<D> { record() }
    func onLeak<D>(factory: SyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) throws -> LeakedResolutionStrategy<D> { record() }
    func onLeak<D>(factory: AsyncFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async -> LeakedResolutionStrategy<D> { record() }
    func onLeak<D>(factory: AsyncThrowingFactory<D>, testContainerFile: String, testContainerLine: UInt, testContainerFunction: String) async throws -> LeakedResolutionStrategy<D> { record() }
}

/// A resolve after its `withTestContainer` block ended trips leak detection, even for a factory
/// marked `useProduction()` or `useParentContainer()`.
struct LeakedResolutionModeTests {
    enum Mode: CaseIterable { case production, parentContainer }

    #if DEBUG
    @Test(arguments: Mode.allCases)
    func leakedResolveOfOptedOutFactoryTripsLeakDetection(mode: Mode) async throws {
        let sync = Factory { LeakModeDep("production") }
        let syncThrowing = Factory { () throws -> LeakModeDep in LeakModeDep("production") }
        let async = Factory { @Sendable () async -> LeakModeDep in LeakModeDep("production") }
        let asyncThrowing = Factory { @Sendable () async throws -> LeakModeDep in LeakModeDep("production") }
        let behavior = RecordingLeakBehavior()

        let leakedContainer = await withTestContainer(leakedResolutionBehavior: behavior) {
            switch mode {
            case .production:
                sync.useProduction(); syncThrowing.useProduction(); async.useProduction(); asyncThrowing.useProduction()
            case .parentContainer:
                sync.useParentContainer(); syncThrowing.useParentContainer(); async.useParentContainer(); asyncThrowing.useParentContainer()
            }
            // While the block runs, the mode applies and nothing leaks.
            #expect(sync().name == "production")
            return Container.current
        }

        // The block has ended: resolving through its container is a leak.
        try await withContainer(leakedContainer) {
            let a = sync().name
            let b = try syncThrowing().name
            let c = await async().name
            let d = try await asyncThrowing().name
            #expect([a, b, c, d] == ["leaked", "leaked", "leaked", "leaked"])
        }
        #expect(behavior.leaks == 4)
    }
    #endif
}
