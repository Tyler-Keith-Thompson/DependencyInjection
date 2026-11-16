//
//  CycleDetection.swift
//  DependencyInjection
//

import Foundation
import Atomics

/// Detects dependency cycles in debug builds.
///
/// A cycle is a resolution that can never finish: a factory is resolved again, in the same
/// container, while its own resolution is still waiting on the result. A sync cycle overflows
/// the stack, an async cycle through `.unique` recurses forever, and an async cycle through
/// `.cached` or `.shared` waits on itself and hangs. Instead, resolution stops with a message
/// that lists the whole cycle.
///
/// Only work the resolution actually waits on counts: the same task, and the task a cached or
/// shared scope starts and awaits for an async resolver. A `Task { }` started during a
/// resolution inherits task-locals but is not awaited by it, so resolving the same factory
/// from there is not a cycle (for example a back-reference that is resolved later, from the
/// cache). Cycles through `async let`, task groups, or a `Task` the resolver awaits are not
/// detected, because Swift gives no way to tell those apart from tasks nobody waits on.
enum CycleDetection {
    struct Step: Sendable {
        let factory: ObjectIdentifier
        let container: ObjectIdentifier
        let dependency: String
        let file: String
        let line: UInt
        let function: String
        let frame: Frame
    }

    /// Whether a step's resolution is still running. Guards against task addresses being reused.
    final class Frame: Sendable {
        private let active = ManagedAtomic(true)
        var isActive: Bool { active.load(ordering: .acquiring) }
        func finish() { active.store(false, ordering: .releasing) }
    }

    struct Path: Sendable {
        /// The task (or thread, outside a task) that is waiting on every step in `steps`.
        let owner: Int
        let steps: [Step]
    }

    @TaskLocal static var path: Path?

    static func resolving<F: _Factory, T>(_ factory: F,
                                          file: String, line: UInt, function: String,
                                          _ resolve: () throws -> T) rethrows -> T {
        #if DEBUG
        let (path, frame) = enter(factory, file: file, line: line, function: function)
        defer { frame.finish() }
        return try $path.withValue(path) {
            try resolve()
        }
        #else
        return try resolve()
        #endif
    }

    static func resolving<F: _Factory, T: Sendable>(_ factory: F,
                                                    file: String, line: UInt, function: String,
                                                    _ resolve: () async throws -> T) async rethrows -> T {
        #if DEBUG
        let (path, frame) = enter(factory, file: file, line: line, function: function)
        defer { frame.finish() }
        return try await $path.withValue(path) {
            try await resolve()
        }
        #else
        return try await resolve()
        #endif
    }

    /// The steps the current task is waiting on, to hand to a task that it will await.
    static func handOff() -> [Step] {
        #if DEBUG
        return waitingSteps()
        #else
        return []
        #endif
    }

    /// Runs `body` in a task that the steps' resolutions are awaiting, so they stay on its path.
    static func adopting<T: Sendable>(_ steps: [Step],
                                      isolation: isolated (any Actor)? = #isolation,
                                      _ body: () async throws -> T) async rethrows -> T {
        #if DEBUG
        return try await $path.withValue(Path(owner: currentOwner(), steps: steps), operation: {
            try await body()
        }, isolation: isolation)
        #else
        return try await body()
        #endif
    }

    private static func enter<F: _Factory>(_ factory: F, file: String, line: UInt, function: String) -> (Path, Frame) {
        let step = Step(factory: ObjectIdentifier(factory),
                        container: ObjectIdentifier(Container.current),
                        dependency: String(describing: F.Dependency.self),
                        file: file, line: line, function: function,
                        frame: Frame())
        let steps = waitingSteps()
        if let start = steps.firstIndex(where: { $0.factory == step.factory && $0.container == step.container }) {
            fatalError(message(for: Array(steps[start...]) + [step]))
        }
        return (Path(owner: currentOwner(), steps: steps + [step]), step.frame)
    }

    private static func waitingSteps() -> [Step] {
        guard let path, path.owner == currentOwner() else { return [] }
        return path.steps.filter(\.frame.isActive)
    }

    private static func currentOwner() -> Int {
        withUnsafeCurrentTask { task in
            task?.hashValue ?? pthread_self().hashValue
        }
    }

    static func message(for cycle: [Step]) -> String {
        let chain = cycle.enumerated().map { index, step in
            let arrow = index == 0 ? "  " : "  → "
            let fileName = step.file.split(separator: "/").last.map(String.init) ?? step.file
            return "\(arrow)\(step.dependency)  (resolved at \(fileName):\(step.line) in \(step.function))"
        }
        return """
        Dependency cycle detected: \(cycle[0].dependency) depends on itself.
        \(chain.joined(separator: "\n"))
        Resolving it would never finish. Break the cycle, for example by passing one of these dependencies in as a parameter instead of injecting it.
        """
    }
}
