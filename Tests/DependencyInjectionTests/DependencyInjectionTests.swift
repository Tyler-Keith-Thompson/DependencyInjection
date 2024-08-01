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
        class Super {
            init() async { }
        }
        let factory = Factory { await Super() }
        
        #expect(await factory() !== factory())
    }
    
    @Test func asynchronousThrowingFactoryCanResolveAUniqueType() async throws {
        class Super {
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
        class Super {
            init() async { }
        }
        class Sub: Super { }
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
        class Super {
            init() async throws { }
        }
        class Sub: Super { }
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