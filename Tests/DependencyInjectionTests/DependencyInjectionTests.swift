import Testing
import DependencyInjection

struct DependencyInjectionTests {
    @Test func synchronousFactoryCanResolveAUniqueType() async throws {
        class Super { }
        let factory = Factory { Super() }
        
        #expect(factory() !== factory())
    }
    
    @Test func synchronousThrowingFactoryCanResolveAUniqueType() async throws {
        class Super {
            init() throws { }
        }
        let factory = Factory { try Super() }
        
        #expect(try factory() !== factory())
    }
    
    @Test func asynchronousFactoryCanResolveAUniqueType() async throws {
        actor Super {
            init() async { }
        }
        let factory = Factory { await Super() }
        
        #expect(await factory() !== factory())
    }
    
    @Test func asynchronousThrowingFactoryCanResolveAUniqueType() async throws {
        actor Super {
            init() async throws { }
        }
        let factory = Factory { try await Super() }
        
        #expect(try await factory() !== factory())
    }
    
    @Test func factoryCanRegisterANewType() async throws {
        class Super { }
        class Sub: Super { }
        let factory = Factory { Super() }
        
        #expect(factory() !== factory())
        
        factory.register { Sub() }
        #expect(factory() is Sub)
    }
    
    @Test func synchronousFactoryCanResolveWithHierarchicalContainers() async throws {
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
    
    @Test func synchronousThrowingFactoryCanResolveWithHierarchicalContainers() async throws {
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
    
    @Test func asynchronousFactoryCanResolveWithHierarchicalContainers() async throws {
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

    @Test func asynchronousThrowingFactoryCanResolveWithHierarchicalContainers() async throws {
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
    
    @Test func synchronousFactoryCanResolveWithACachedScope() async throws {
        class Super { }
        let factory = Factory(scope: .cached) { Super() }
        
        #expect(factory() === factory())
    }
    
    @Test func synchronousThrowingFactoryCanResolveWithACachedScope() async throws {
        class Super {
            init() throws { }
        }
        let factory = Factory(scope: .cached) { try Super() }
        
        #expect(try factory() === factory())
    }
    
    @Test func asynchronousFactoryCanResolveWithACachedScope() async throws {
        actor Super {
            init() async { }
        }
        let factory = Factory(scope: .cached) { await Super() }
        
        #expect(await factory() === factory())
    }
    
    @Test func asynchronousThrowingFactoryCanResolveWithACachedScope() async throws {
        actor Super {
            init() async throws { }
        }
        let factory = Factory(scope: .cached) { try await Super() }
        
        #expect(try await factory() === factory())
    }
    
    @Test func asynchronousFactoryCanResolveInParallelWithACachedScope() async throws {
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
    
    @Test func asynchronousThrowingFactoryCanResolveInParallelWithACachedScope() async throws {
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
    
    @Test func synchronousFactoryCanResolveWithASharedScope() async throws {
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
    
    @Test func synchronousThrowingFactoryCanResolveWithASharedScope() async throws {
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
    
    @Test func asynchronousFactoryCanResolveWithASharedScope() async throws {
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
    
    @Test func asynchronousThrowingFactoryCanResolveWithASharedScope() async throws {
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

    @Test func asynchronousFactoryCanResolveInParallelWithASharedScope() async throws {
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
    
    @Test func asynchronousThrowingFactoryCanResolveInParallelWithASharedScope() async throws {
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
