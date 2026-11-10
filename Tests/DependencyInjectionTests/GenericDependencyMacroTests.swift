//
//  GenericDependencyMacroTests.swift
//  DependencyInjection
//

import Testing
import DependencyInjection

// The macros generate `$property: <Factory><T>`. These tests use generic dependency types
// (including generic arguments that contain commas) so a wrong `T` fails to compile.

final class GenericBox<Value: Sendable>: Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private extension Container {
    static let genericSync = Factory { GenericBox(1) }
    static let genericSyncThrowing = Factory { () throws -> GenericBox<Int> in GenericBox(1) }
    static let genericAsync = Factory { @Sendable () async -> GenericBox<Int> in GenericBox(1) }
    static let genericAsyncThrowing = Factory { @Sendable () async throws -> GenericBox<Int> in GenericBox(1) }
    static let dictionarySyncThrowing = Factory { () throws -> Dictionary<String, Int> in ["a": 1] }
    static let dictionaryAsync = Factory { @Sendable () async -> Dictionary<String, Int> in ["a": 1] }
}

struct GenericDependencyMacroTests {
    final class InjectedExample {
        @Injected(Container.genericSync) var sync: GenericBox<Int>
        @Injected(Container.genericSyncThrowing) var syncThrowing: Result<GenericBox<Int>, any Error>
        @Injected(Container.genericAsync) var async: Task<GenericBox<Int>, Never>
        @Injected(Container.genericAsyncThrowing) var asyncThrowing: Task<GenericBox<Int>, any Error>
        @Injected(Container.dictionarySyncThrowing) var dictionary: Swift.Result<Dictionary<String, Int>, any Error>
        @Injected(Container.dictionaryAsync) var dictionaryTask: Task<Dictionary<String, Int>, Never>
    }

    final class LazyInjectedExample {
        @LazyInjected(Container.genericSync) var sync: GenericBox<Int>
        @LazyInjected(Container.genericSyncThrowing) var syncThrowing: Result<GenericBox<Int>, any Error>
        @LazyInjected(Container.genericAsync) var async: Task<GenericBox<Int>, Never>
        @LazyInjected(Container.genericAsyncThrowing) var asyncThrowing: Task<GenericBox<Int>, any Error>
        @LazyInjected(Container.dictionarySyncThrowing) var dictionary: Result<Dictionary<String, Int>, any Error>
    }

    final class ConstructorInjectedExample {
        @ConstructorInjected(Container.genericSync) var sync: GenericBox<Int>
        @ConstructorInjected(Container.genericSyncThrowing) var syncThrowing: Result<GenericBox<Int>, any Error>
        @ConstructorInjected(Container.genericAsync) var async: Task<GenericBox<Int>, Never>
        @ConstructorInjected(Container.genericAsyncThrowing) var asyncThrowing: Task<GenericBox<Int>, any Error>
        @ConstructorInjected(Container.dictionaryAsync) var dictionaryTask: Task<Dictionary<String, Int>, Never>
    }

    @Test func injectedProjectsFactoryOfGenericDependencyType() async throws {
        try await withTestContainer {
            let example = InjectedExample()
            let sync: SyncFactory<GenericBox<Int>> = example.$sync
            let syncThrowing: SyncThrowingFactory<GenericBox<Int>> = example.$syncThrowing
            let async: AsyncFactory<GenericBox<Int>> = example.$async
            let asyncThrowing: AsyncThrowingFactory<GenericBox<Int>> = example.$asyncThrowing
            let dictionary: SyncThrowingFactory<Dictionary<String, Int>> = example.$dictionary
            let dictionaryTask: AsyncFactory<Dictionary<String, Int>> = example.$dictionaryTask

            sync.register { GenericBox(2) }
            syncThrowing.register { GenericBox(3) }
            async.register { GenericBox(4) }
            asyncThrowing.register { GenericBox(5) }
            dictionary.register { ["b": 2] }
            dictionaryTask.register { ["c": 3] }

            #expect(example.sync.value == 2)
            let v1 = try example.syncThrowing.get().value
            #expect(v1 == 3)
            let v2 = await example.async.value.value
            #expect(v2 == 4)
            let v3 = try await example.asyncThrowing.value.value
            #expect(v3 == 5)
            let v4 = try example.dictionary.get()
            #expect(v4 == ["b": 2])
            let v5 = await example.dictionaryTask.value
            #expect(v5 == ["c": 3])
        }
    }

    @Test func lazyInjectedProjectsFactoryOfGenericDependencyType() async throws {
        try await withTestContainer {
            let example = LazyInjectedExample()
            let sync: SyncFactory<GenericBox<Int>> = example.$sync
            let syncThrowing: SyncThrowingFactory<GenericBox<Int>> = example.$syncThrowing
            let async: AsyncFactory<GenericBox<Int>> = example.$async
            let asyncThrowing: AsyncThrowingFactory<GenericBox<Int>> = example.$asyncThrowing
            let dictionary: SyncThrowingFactory<Dictionary<String, Int>> = example.$dictionary

            sync.register { GenericBox(2) }
            syncThrowing.register { GenericBox(3) }
            async.register { GenericBox(4) }
            asyncThrowing.register { GenericBox(5) }
            dictionary.register { ["b": 2] }

            #expect(example.sync.value == 2)
            let v6 = try example.syncThrowing.get().value
            #expect(v6 == 3)
            let v7 = await example.async.value.value
            #expect(v7 == 4)
            let v8 = try await example.asyncThrowing.value.value
            #expect(v8 == 5)
            let v9 = try example.dictionary.get()
            #expect(v9 == ["b": 2])
        }
    }

    @Test func constructorInjectedProjectsFactoryOfGenericDependencyType() async throws {
        try await withTestContainer {
            Container.genericSync.register { GenericBox(2) }
            Container.genericSyncThrowing.register { GenericBox(3) }
            Container.genericAsync.register { GenericBox(4) }
            Container.genericAsyncThrowing.register { GenericBox(5) }
            Container.dictionaryAsync.register { ["c": 3] }

            let example = ConstructorInjectedExample()
            let _: SyncFactory<GenericBox<Int>> = example.$sync
            let _: SyncThrowingFactory<GenericBox<Int>> = example.$syncThrowing
            let _: AsyncFactory<GenericBox<Int>> = example.$async
            let _: AsyncThrowingFactory<GenericBox<Int>> = example.$asyncThrowing
            let _: AsyncFactory<Dictionary<String, Int>> = example.$dictionaryTask

            #expect(example.sync.value == 2)
            let v10 = try example.syncThrowing.get().value
            #expect(v10 == 3)
            let v11 = await example.async.value.value
            #expect(v11 == 4)
            let v12 = try await example.asyncThrowing.value.value
            #expect(v12 == 5)
            let v13 = await example.dictionaryTask.value
            #expect(v13 == ["c": 3])
        }
    }
}
