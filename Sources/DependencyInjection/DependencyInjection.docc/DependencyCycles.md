# Dependency cycles

Find the factories that depend on each other in a loop.

## What you see

In debug builds, resolving a factory that is already being resolved further up the same chain stops at once and prints the cycle:

```
Dependency cycle detected: CycleA depends on itself.
  CycleA  (resolved at AppView.swift:20 in body)
  → CycleB  (resolved at CycleA.swift:12 in CycleA)
  → CycleA  (resolved at CycleB.swift:15 in CycleB)
```

Without the check, a sync cycle overflows the stack and an async `.cached` or `.shared` cycle hangs. Release builds skip it.

## What counts as a cycle

Only resolutions that can never finish are reported: the same factory, in the same container, resolved again while its own resolution is still waiting for the result. That covers direct calls, sync and async, and the task a `.cached` or `.shared` scope awaits for an async resolver.

These are not reported:

- A back-reference resolved from a `Task { }` that the owner starts but doesn't wait on, including the tasks `@ConstructorInjected` and `@LazyInjected` start for async factories. That resolution can still finish.
- Cycles through `async let`, task groups, or a `Task` the resolver awaits. Swift can't tell those tasks apart from ones nobody waits on.
- An async `.cached` or `.shared` cycle that two callers enter at the same time from different factories, one resolving A then B while the other resolves B then A. Each scope's task carries only the chain of the caller that started it, so the two wait on each other and hang.

Two types that inject each other with macros also need explicit factory types to compile; see <doc:InjectionMacros>.
