# Architecture

How containers, factories, scopes and test containers fit together, and what keeps them thread-safe.

## Components

```
Container                    The resolution context; holds per-factory storage
  |-- Storage<Factory>       LIFO registration stack per factory
  |-- parent: Container?     Parent for hierarchical fallback
  '-- fatalErrorOnResolve    Atomic flag for test leak detection

Factory (Sync|SyncThrowing|Async|AsyncThrowing)
  |-- resolver               The default production closure
  |-- scope                  Lifetime strategy (unique/cached/shared)
  |-- register()             Push an override onto the current container's stack
  |-- popRegistration()      Pop the most recent override
  '-- callAsFunction()       Resolve through Container.current

Scope
  |-- UniqueScope            Always calls the resolver
  |-- CachedScope            Per-container strong cache + async task deduplication
  '-- SharedScope            Per-container weak cache + async task deduplication

TestContainer (extends Container)
  |-- executingTest           Atomic flag for leak detection window
  |-- unregisteredBehavior    What to do when a factory has no test double
  '-- leakedResolutionBehavior  What to do when resolution escapes test scope

Macros (@Injected, @LazyInjected, @ConstructorInjected)
  '-- Expand to resolver types + computed property + projected value
```

## Resolution

Calling `factory()`, or reading an `@Injected` property:

1. finds the current container through `ServiceContext`, or the default container if none is set;
2. looks in that container's registration stack for the factory;
3. if it finds one, applies the scope: `.unique` creates an instance, and `.cached` and `.shared` check the cache first;
4. if not, moves to the parent container and repeats;
5. if no container has an override, uses the factory's own resolver with its scope.

In a test container with no registration for the factory, the leaked resolution behavior runs if the test's block has already exited, and the unregistered behavior (`fatalError` by default) runs if it hasn't.

## Thread safety

| Mechanism | Where |
|---|---|
| `NSRecursiveLock` | Container storage, registration stacks, scope caches, `@LazyInjected` storage |
| `ManagedAtomic<Bool>` | The default container's crash-on-resolve flag, a test container's executing flag |
| `ManagedAtomic<UInt8>` | Each test container's `useProduction()` / `useParentContainer()` mode |
| `ManagedAtomic<Int>` | Counting concurrent `withTestContainer` entries and exits |
| A global actor | Serializing async `.cached` and `.shared` resolution, so there is never a duplicate task |
| `ServiceContext` (task-local) | Carrying the current container through structured concurrency |

## Caches and containers

The strong and weak caches key their entries by container identity. As a result:

- each `withTestContainer` block gets its own cache entries;
- concurrent tests never share a `.cached` instance;
- in production, the default container's entries last as you'd expect;
- cache lookups never go above a test container. A `withNestedContainer` inside a test reads values cached in itself, its parents and the test container, but nothing cached above the test container.

Registering a resolver on a `.cached` or `.shared` factory clears its cache, so the next resolution uses the new resolver.
