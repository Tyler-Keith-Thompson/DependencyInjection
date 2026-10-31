# DependencyInjection: triage charter

## What it is
A Swift 6 dependency-injection library for Swift app and server code. You register dependencies
as `Factory` values on `Container`, get them through macros or by calling the factory, and swap
them per test. The thing it optimizes for is isolating tests that run concurrently: a test's
registrations, caches and leftover async work must never leak into another test.

## In scope
- Factories: the sync, sync-throwing, async and async-throwing variants, and calling a factory to resolve.
- Scopes: `.unique`, `.cached`, `.shared`, plus dedup of concurrent async resolutions.
- Containers: the hierarchy, parent fallback, carrying `Container.current` through ServiceContext, `withContainer`.
- Injection macros: `@Injected`, `@LazyInjected`, `@ConstructorInjected` and their `$` projections.
- Test support: `withTestContainer`, what happens on an unregistered resolve, leak detection and its behaviors, composable test defaults.
- DispatchInterpose: the C shim that carries test context across GCD calls.
- Platforms: Apple platforms at the current floor and Linux (CI runs on swift:6.1.2 Ubuntu).
  Windows and Android support are welcome as backlog features (see D5).
- Licensing, DocC docs and the README.

## Not in scope
- N1. Runtime or reflection-based auto-wiring (resolving by type alone, scanning constructors). Factories are explicit, typed values, and that's the design.
- N2. String or key-based lookup and service-locator registries. A dependency is a `Factory` constant, not a name.
- N3. Integrations with specific frameworks (SwiftUI `@Environment` bridges, Vapor, TCA adapters). The owner has explicitly declined an `@Environment` bridge. These belong in a separate package that builds on this one, if anywhere.
- N4. Shipping the macros as their own product or public API. Since 04ee9e3 they're an implementation detail of the `DependencyInjection` product.
- N5. Anything that weakens test isolation for convenience, for example sharing caches between test containers, or a silent fallback to production on an unregistered resolve outside the opt-in best-effort behavior.
- N6. Support for Swift before 6 or for language modes other than 6.
- N7. Mocking or spy generation. Users write their own test doubles, and the library only swaps them in.
- N8. Lowering the platform floor (iOS 17 / macOS 13 / watchOS 10 / tvOS 17). It stays where it is.

## Rules a request must fit
- Swift 6 strict concurrency: every public type is `Sendable`, with no `@unchecked` escape hatch unless it's justified.
- No public test-only hooks. Test support goes through `withTestContainer` and test defaults (the test container itself was made non-public on purpose).
- Each of the four factory variants (sync / throwing / async / async-throwing) needs a counterpart. A feature built for only one variant isn't done.
- Has to build and pass on Linux. Platform-specific code goes behind `#if`.
- New dependencies: only Apple's swift-* packages. Pulling in a third-party runtime dependency needs the owner's sign-off.
- A behavior change to resolution, caching or isolation comes with a concurrency test that proves it.

## Belongs elsewhere
- Bugs in ServiceContext, swift-atomics or swift-syntax → the matching apple/* repo upstream. Work around them here only if a release is blocked.
- Questions about using the library in a particular app → that app's backlog, not this one.
- Framework bridges (SwiftUI, Vapor, TCA) → a separate package, not this repo (N3).

## Kinds, labels and Ready
- bug: wrong resolution, scope, isolation or leak-detection behavior, or a build failure on a supported platform.
- friction: an API that works but takes too many tries or hides the cause (an unclear fatalError message, for example).
- docs: README/DocC that's wrong, missing or misleading.
- feature: a new capability that fits In scope and the Rules.
- Ready means the item names the affected factory variants and scopes, says whether it touches test isolation, and has a repro or a sketch of the intended call site.

## Decisions
- D1. "Detached tasks lose the container" → works as designed. Use `withContainer`, as the README documents.
- D2. "Expose the macros module as a product" → no, see N4.
- D3. "Unregistered resolutions in tests should fall back to production" → no. They crash by default so missing doubles get noticed. `BestEffortLeakedResolutionBehavior` / `DI_BEST_EFFORT_LEAK_RESOLUTION` are the only opt-out, and only for leaked resolutions.
- D4. License → Apache-2.0 (DI-1). Accept it to the Backlog, not Ready. The owner hasn't scheduled it yet, so an agent shouldn't add the LICENSE file unprompted.
- D5. Windows / Android support → accept as a feature into the Backlog. DispatchInterpose and other Darwin/Linux-specific code is the expected work. It must not regress Apple or Linux.

## Open questions
- None outstanding.
