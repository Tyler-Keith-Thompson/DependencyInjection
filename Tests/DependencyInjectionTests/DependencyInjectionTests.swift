import Foundation
import Testing
import DependencyInjection

struct DependencyInjectionTests {
    @Test func synchronousFactoryCanResolveAUniqueType() async throws {
        withNestedContainer {
            class Super { }
            let factory = Factory { Super() }
            
            #expect(factory() !== factory())
        }
    }
    
    @Test func synchronousThrowingFactoryCanResolveAUniqueType() async throws {
        try withNestedContainer {
            class Super {
                init() throws { }
            }
            let factory = Factory { try Super() }
            
            let first = try factory()
            let second = try factory()
            #expect(first !== second)
        }
    }
    
    @Test func asynchronousFactoryCanResolveAUniqueType() async throws {
        await withNestedContainer {
            actor Super {
                init() async { }
            }
            let factory = Factory { await Super() }
            
            #expect(await factory() !== factory())
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveAUniqueType() async throws {
        try await withNestedContainer {
            actor Super {
                init() async throws { }
            }
            let factory = Factory { try await Super() }
            
            let first = try await factory()
            let second = try await factory()
            #expect(first !== second)
        }
    }
    
    @Test func factoryCanRegisterANewType() async throws {
        withNestedContainer {
            class Super { }
            class Sub: Super { }
            let factory = Factory { Super() }
            
            #expect(factory() !== factory())
            
            factory.register { Sub() }
            #expect(factory() is Sub)
        }
    }
    
    @Test func synchronousFactoryCanUnregisterANewType() async throws {
        withNestedContainer {
            class Super { }
            class Sub: Super { }
            let factory = Factory { Super() }
            
            #expect(factory() !== factory())
            
            factory.register { Sub() }
            #expect(factory() is Sub)
            factory.popRegistration()
            #expect(!(factory() is Sub))
        }
    }
    
    @Test func synchronousThrowingFactoryCanUnregisterANewType() async throws {
        try withNestedContainer {
            class Super {
                init() throws { }
            }
            class Sub: Super { }
            let factory = Factory { try Super() }.popRegistration()
            
            let first = try factory()
            let second = try factory()
            #expect(first !== second)
            
            factory.register { try Sub() }
            #expect(try factory() is Sub)
            factory.popRegistration()
            #expect(!(try factory() is Sub))
        }
    }
    
    @Test func asynchronousFactoryCanUnregisterANewType() async throws {
        await withNestedContainer {
            class Super: @unchecked Sendable {
                init() async { }
            }
            class Sub: Super, @unchecked Sendable { }
            let factory = Factory { await Super() }.popRegistration()
            
            #expect(await factory() !== factory())
            
            factory.register { await Sub() }
            #expect(await factory() is Sub)
            factory.popRegistration()
            #expect(!(await factory() is Sub))
        }
    }
    
    @Test func asynchronousThrowingFactoryCanUnregisterANewType() async throws {
        try await withNestedContainer {
            class Super: @unchecked Sendable {
                init() async throws { }
            }
            class Sub: Super, @unchecked Sendable { }
            let factory = Factory { try await Super() }.popRegistration()
            
            let first = try await factory()
            let second = try await factory()
            #expect(first !== second)
            
            factory.register { try await Sub() }
            #expect(try await factory() is Sub)
            factory.popRegistration()
            #expect(!(try await factory() is Sub))
        }
    }
    
    @Test func synchronousFactoryCanResolveWithHierarchicalContainers() async throws {
        withNestedContainer {
            class Super { }
            class Sub: Super { }
            let factory = Factory { Super() }
            
            #expect(factory() !== factory())
            
            withNestedContainer {
                factory.register { Sub() }
                #expect(factory() is Sub)
            }
            
            #expect(!(factory() is Sub))
        }
    }
    
    @Test func synchronousThrowingFactoryCanResolveWithHierarchicalContainers() async throws {
        try withNestedContainer {
            class Super {
                init() throws { }
            }
            class Sub: Super { }
            let factory = Factory { try Super() }
            
            #expect(try factory() !== factory())
            
            try withNestedContainer {
                factory.register { try Sub() }
                let resolved = try factory()
                #expect(resolved is Sub)
            }
            
            #expect(!(try factory() is Sub))
        }
    }
    
    @Test func asynchronousFactoryCanResolveWithHierarchicalContainers() async throws {
        await withNestedContainer {
            class Super: @unchecked Sendable {
                init() async { }
            }
            class Sub: Super, @unchecked Sendable { }
            let factory = Factory { await Super() }
            
            #expect(await factory() !== factory())
            
            await withNestedContainer {
                factory.register { await Sub() }
                let resolved = await factory()
                #expect(resolved is Sub)
            }
            
            #expect(!(await factory() is Sub))
        }
    }

    @Test func asynchronousThrowingFactoryCanResolveWithHierarchicalContainers() async throws {
        try await withNestedContainer {
            class Super: @unchecked Sendable {
                init() async throws { }
            }
            class Sub: Super, @unchecked Sendable { }
            let factory = Factory { try await Super() }
            
            #expect(try await factory() !== factory())
            
            try await withNestedContainer {
                factory.register { try await Sub() }
                let resolved = try await factory()
                #expect(resolved is Sub)
            }
            
            #expect(!(try await factory() is Sub))
        }
    }
    
    @Test func synchronousFactoryCanResolveFromParentWithHierarchicalContainers() async throws {
        withNestedContainer {
            class Super { }
            class Sub: Super { }
            class SubSub: Super { }
            let factory = Factory { Super() }
            factory.register { Sub() }
            
            #expect(factory() !== factory())
            
            withNestedContainer {
                #expect(factory() is Sub)
                factory.register { SubSub() }
                #expect(factory() is SubSub)
                factory.popRegistration()
                #expect(factory() is Sub)
            }
            
            #expect(factory() is Sub)
        }
    }
    
    @Test func synchronousThrowingFactoryCanResolveFromParentWithHierarchicalContainers() async throws {
        try withNestedContainer {
            class Super {
                init() throws { }
            }
            class Sub: Super { }
            class SubSub: Super { }
            let factory = Factory { try Super() }
            factory.register { try Sub() }
            
            #expect(try factory() !== factory())
            
            try withNestedContainer {
                var val = try factory()
                #expect(val is Sub)
                factory.register { try SubSub() }
                val = try factory()
                #expect(val is SubSub)
                factory.popRegistration()
                val = try factory()
                #expect(val is Sub)
            }
            
            #expect(try factory() is Sub)
        }
    }
    
    @Test func asynchronousFactoryCanResolveFromParentWithHierarchicalContainers() async throws {
        await withNestedContainer {
            class Super: @unchecked Sendable {
                init() async { }
            }
            class Sub: Super, @unchecked Sendable { }
            class SubSub: Super, @unchecked Sendable { }
            let factory = Factory { await Super() }
            factory.register { await Sub() }
            
            #expect(await factory() !== factory())
            
            await withNestedContainer {
                var val = await factory()
                #expect(val is Sub)
                factory.register { await SubSub() }
                val = await factory()
                #expect(val is SubSub)
                factory.popRegistration()
                val = await factory()
                #expect(val is Sub)
            }
            
            #expect(await factory() is Sub)
        }
    }

    @Test func asynchronousThrowingFactoryCanResolveFromParentWithHierarchicalContainers() async throws {
        try await withNestedContainer {
            class Super: @unchecked Sendable {
                init() async throws { }
            }
            class Sub: Super, @unchecked Sendable { }
            class SubSub: Super, @unchecked Sendable { }
            let factory = Factory { try await Super() }
            factory.register { try await Sub() }
            
            #expect(try await factory() !== factory())
            
            try await withNestedContainer {
                var val = try await factory()
                #expect(val is Sub)
                factory.register { try await SubSub() }
                val = try await factory()
                #expect(val is SubSub)
                factory.popRegistration()
                val = try await factory()
                #expect(val is Sub)
            }
            
            #expect(try await factory() is Sub)
        }
    }
    
    @Test func synchronousFactoryCanResolveWithACachedScope() async throws {
        withNestedContainer {
            class Super { }
            let factory = Factory(scope: .cached) { Super() }
            
            #expect(factory() === factory())
        }
    }
    
    @Test func synchronousThrowingFactoryCanResolveWithACachedScope() async throws {
        try withNestedContainer {
            class Super {
                init() throws { }
            }
            let factory = Factory(scope: .cached) { try Super() }
            
            let first = try factory()
            let second = try factory()
            #expect(first === second)
        }
    }
    
    @Test func asynchronousFactoryCanResolveWithACachedScope() async throws {
        await withNestedContainer {
            actor Super {
                init() async { }
            }
            let factory = Factory(scope: .cached) { await Super() }
            
            #expect(await factory() === factory())
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveWithACachedScope() async throws {
        try await withNestedContainer {
            actor Super {
                init() async throws { }
            }
            let factory = Factory(scope: .cached) { try await Super() }
            
            let first = try await factory()
            let second = try await factory()
            #expect(first === second)
        }
    }
    
    @Test func asynchronousFactoryCanResolveInParallelWithACachedScope() async throws {
        await withNestedContainer {
            actor Super {
                init() async { }
            }
            let factory = Factory(scope: .cached) { await Super() }
            
            async let factory1 = await factory()
            async let factory2 = await factory()
            let resolved1 = await factory1
            let resolved2 = await factory2
            
            #expect(resolved1 === resolved2)
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveInParallelWithACachedScope() async throws {
        try await withNestedContainer {
            actor Super {
                init() async throws { }
            }
            let factory = Factory(scope: .cached) { try await Super() }
            
            async let factory1 = try await factory()
            async let factory2 = try await factory()
            let resolved1 = try await factory1
            let resolved2 = try await factory2
            
            #expect(resolved1 === resolved2)
        }
    }
    
    @Test func synchronousFactoryCanResolveWithASharedScope() async throws {
        withNestedContainer {
            class Super { }
            var count = 0
            let factory = Factory(scope: .shared) { count += 1; return Super() }
            var val: Super? = factory()
            weak var ref = val
            
            #expect(ref != nil)
            #expect(val === factory())
            #expect(factory() === factory())
            val = nil
            #expect(ref == nil)
            _ = factory()
            #expect(count == 2)
        }
    }
    
    @Test func synchronousThrowingFactoryCanResolveWithASharedScope() async throws {
        try withNestedContainer {
            class Super {
                init() throws { }
            }
            var count = 0
            let factory = Factory(scope: .shared) { count += 1; return try Super() }
            var val: Super? = try factory()
            weak var ref = val
            
            #expect(ref != nil)
            #expect(try val === factory())
            #expect(try factory() === factory())
            val = nil
            #expect(ref == nil)
            _ = try factory()
            #expect(count == 2)
        }
    }
    
    @Test func asynchronousFactoryCanResolveWithASharedScope() async throws {
        await withNestedContainer {
            actor Super {
                init() async { }
            }
            actor Test {
                var count = 0
                func increment() {
                    count += 1
                }
            }
            let test = Test()
            let factory = Factory(scope: .shared) { await test.increment(); return await Super() }
            var val: Super? = await factory()
            weak var ref = val
            
            #expect(ref != nil)
            #expect(await val === factory())
            #expect(await factory() === factory())
            val = nil
            #expect(ref == nil)
            _ = await factory()
            let countVal = await test.count
            #expect(countVal == 2)
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveWithASharedScope() async throws {
        try await withNestedContainer {
            actor Super {
                init() async throws { }
            }
            actor Test {
                var count = 0
                func increment() {
                    count += 1
                }
            }
            let test = Test()
            let factory = Factory(scope: .shared) { await test.increment(); return try await Super() }
            var val: Super? = try await factory()
            weak var ref = val
            
            #expect(ref != nil)
            #expect(try await val === factory())
            #expect(try await factory() === factory())
            val = nil
            #expect(ref == nil)
            _ = try await factory()
            let countVal = await test.count
            #expect(countVal == 2)
        }
    }

    @Test func asynchronousFactoryCanResolveInParallelWithASharedScope() async throws {
        await withNestedContainer {
            actor Super {
                init() async { }
            }
            let factory = Factory(scope: .shared) { await Super() }
            
            async let factory1 = await factory()
            async let factory2 = await factory()
            let resolved1 = await factory1
            let resolved2 = await factory2
            
            #expect(resolved1 === resolved2)
        }
    }
    
    @Test func asynchronousThrowingFactoryCanResolveInParallelWithASharedScope() async throws {
        try await withNestedContainer {
            actor Super {
                init() async throws { }
            }
            let factory = Factory(scope: .shared) { try await Super() }
            
            async let factory1 = try await factory()
            async let factory2 = try await factory()
            let resolved1 = try await factory1
            let resolved2 = try await factory2
            
            #expect(resolved1 === resolved2)
        }
    }

    @Test func synchronousFactoryCanResolveWithASharedScope_whenResolvedConcurrently() async {
        await withNestedContainer {
            class Super: @unchecked Sendable {
                // we're using semaphores here because we need to be able to prevent
                // the synchronous init from finishing until both Tasks have begun
                static let semaphore1 = DispatchSemaphore(value: 1)
                static let semaphore2 = DispatchSemaphore(value: 1)

                init() {
                    #expect(Self.semaphore1.wait(timeout: .now() + 0.1) == .success)
                    #expect(Self.semaphore2.wait(timeout: .now() + 0.1) == .success)
                    Self.semaphore1.signal()
                    Self.semaphore2.signal()
                }
                static let service = Factory(scope: .shared) { Super() }
            }

            struct Test: Sendable {
                @Injected(Super.service) var injectedService
            }

            let test = Test()

            #expect(Super.semaphore1._wait(timeout: .now() + 0.1) == .success)
            #expect(Super.semaphore2._wait(timeout: .now() + 0.1) == .success)
            async let _first = Task {
                Super.semaphore1.signal()
                return test.injectedService
            }.value
            async let _second = Task {
                Super.semaphore2.signal()
                return test.injectedService
            }.value
            let first = await _first
            let second = await _second

            #expect(first === second)

            (test.$injectedService.scope as? SharedScope)?.cache.clear()

            #expect(first !== test.injectedService)
        }
    }

    @Test func synchronousThrowingFactoryCanResolveWithASharedScope_whenResolvedConcurrently() async throws {
        try await withNestedContainer {
            class Super: @unchecked Sendable {
                // we're using semaphores here because we need to be able to prevent
                // the synchronous init from finishing until both Tasks have begun
                static let semaphore1 = DispatchSemaphore(value: 1)
                static let semaphore2 = DispatchSemaphore(value: 1)

                init() throws {
                    #expect(Self.semaphore1.wait(timeout: .now() + 0.1) == .success)
                    #expect(Self.semaphore2.wait(timeout: .now() + 0.1) == .success)
                    Self.semaphore1.signal()
                    Self.semaphore2.signal()
                }
                static let service = Factory(scope: .shared) { try Super() }
            }

            struct Test: Sendable {
                @Injected(Super.service) var injectedService
            }

            let test = Test()

            #expect(Super.semaphore1._wait(timeout: .now() + 0.1) == .success)
            #expect(Super.semaphore2._wait(timeout: .now() + 0.1) == .success)
            async let _first = Task {
                Super.semaphore1.signal()
                return test.injectedService
            }.value
            async let _second = Task {
                Super.semaphore2.signal()
                return test.injectedService
            }.value
            let first = try await _first.get()
            let second = try await _second.get()

            #expect(first === second)

            (test.$injectedService.scope as? SharedScope)?.cache.clear()

            let third = try test.injectedService.get()
            #expect(first !== third)
        }
    }

    @Test func synchronousFactoryCanResolveWithACachedScope_whenResolvedConcurrently() async {
        await withNestedContainer {
            class Super: @unchecked Sendable {
                // we're using semaphores here because we need to be able to prevent
                // the synchronous init from finishing until both Tasks have begun
                static let semaphore1 = DispatchSemaphore(value: 1)
                static let semaphore2 = DispatchSemaphore(value: 1)

                init() {
                    #expect(Self.semaphore1.wait(timeout: .now() + 0.1) == .success)
                    #expect(Self.semaphore2.wait(timeout: .now() + 0.1) == .success)
                    Self.semaphore1.signal()
                    Self.semaphore2.signal()
                }
                static let service = Factory(scope: .cached) { Super() }
            }

            struct Test: Sendable {
                @Injected(Super.service) var injectedService
            }
            
            let test = Test()

            #expect(Super.semaphore1._wait(timeout: .now() + 0.1) == .success)
            #expect(Super.semaphore2._wait(timeout: .now() + 0.1) == .success)
            async let _first = Task {
                Super.semaphore1.signal()
                return test.injectedService
            }.value
            async let _second = Task {
                Super.semaphore2.signal()
                return test.injectedService
            }.value
            let first = await _first
            let second = await _second
            
            #expect(first === second)
            
            (test.$injectedService.scope as? CachedScope)?.cache.clear()
            
            #expect(first !== test.injectedService)
        }
    }

    @Test func synchronousThrowingFactoryCanResolveWithACachedScope_whenResolvedConcurrently() async throws {
        try await withNestedContainer {
            class Super: @unchecked Sendable {
                // we're using semaphores here because we need to be able to prevent
                // the synchronous init from finishing until both Tasks have begun
                static let semaphore1 = DispatchSemaphore(value: 1)
                static let semaphore2 = DispatchSemaphore(value: 1)

                init() throws {
                    #expect(Self.semaphore1.wait(timeout: .now() + 0.1) == .success)
                    #expect(Self.semaphore2.wait(timeout: .now() + 0.1) == .success)
                    Self.semaphore1.signal()
                    Self.semaphore2.signal()
                }
                static let service = Factory(scope: .cached) { try Super() }
            }

            struct Test: Sendable {
                @Injected(Super.service) var injectedService
            }

            let test = Test()

            #expect(Super.semaphore1._wait(timeout: .now() + 0.1) == .success)
            #expect(Super.semaphore2._wait(timeout: .now() + 0.1) == .success)
            async let _first = Task {
                Super.semaphore1.signal()
                return test.injectedService
            }.value
            async let _second = Task {
                Super.semaphore2.signal()
                return test.injectedService
            }.value
            let first = try await _first.get()
            let second = try await _second.get()

            #expect(first === second)

            (test.$injectedService.scope as? CachedScope)?.cache.clear()

            let third = try test.injectedService.get()
            #expect(first !== third)
        }
    }
}

extension DispatchSemaphore {
    /// Allows us to use `wait` in async code (against better judgement).
    fileprivate func _wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        self.wait(timeout: timeout)
    }
}
