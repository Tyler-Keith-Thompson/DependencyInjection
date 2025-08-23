//
//  InterposeBridge.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

import Foundation

#if canImport(Darwin)
@_cdecl("transformBlock")
func transformBlock(block: @escaping @convention(block) () -> Void) -> @convention(block) () -> Void {
    let container = Container.current
    return {
        withContainer(container) {
            block()
        }
    }
}
#else
// Linux: Execute work function with container context
@_cdecl("executeWithContainer")
public func executeWithContainer(containerPtr: UnsafeMutableRawPointer?, originalWork: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void, context: UnsafeMutableRawPointer?) {
    print("🔄 executeWithContainer() called from C code!")
    
    guard let containerPtr = containerPtr else {
        print("🔄 No container provided, executing work directly")
        originalWork(context)
        return
    }
    
    let container = Unmanaged<Container>.fromOpaque(containerPtr).takeUnretainedValue()
    print("🔄 Executing with container: \(type(of: container))")
    
    // Check what Container.current is before setting it
    print("🔄 Container.current before withContainer: \(type(of: Container.current))")
    
    withContainer(container) {
        // Check what Container.current is inside withContainer
        print("🔄 Container.current inside withContainer: \(type(of: Container.current))")
        originalWork(context)
    }
    
    // Check what Container.current is after withContainer
    print("🔄 Container.current after withContainer: \(type(of: Container.current))")
}

// Linux: Get current container for C code
@_cdecl("getCurrentContainer")
public func getCurrentContainer() -> UnsafeMutableRawPointer? {
    print("🔍 getCurrentContainer() called from C code!")
    return Unmanaged.passUnretained(Container.current).toOpaque()
}

// Linux: Transform dispatch_block_t to preserve container context
@_cdecl("transformBlockWithContainer")
public func transformBlockWithContainer(containerPtr: UnsafeMutableRawPointer?, block: UnsafeRawPointer) -> UnsafeRawPointer {
    print("🔄 transformBlockWithContainer() called from C code!")
    
    guard let containerPtr = containerPtr else {
        print("🔄 No container provided, returning original block")
        return block
    }
    
    let container = Unmanaged<Container>.fromOpaque(containerPtr).takeUnretainedValue()
    print("🔄 Transforming dispatch_block_t with container: \(type(of: container))")
    
    // dispatch_block_t is @convention(block) () -> Void
    // Convert the raw pointer to this type
    let originalBlock = unsafeBitCast(block, to: (@convention(block) () -> Void).self)
    
    // Create a new block that wraps the original with container context
    let wrappedBlock: @convention(block) () -> Void = {
        print("🔄 Wrapped block executing with container context!")
        
        withContainer(container) {
            print("🔄 Container.current inside withContainer: \(type(of: container))")
            // Execute the original block with the proper container context!
            originalBlock()
        }
        
        print("🔄 Wrapped block execution completed!")
    }
    
    print("🔄 Created wrapped block, storing in registry for C execution")
    
    // Don't return the Swift block directly - instead, let C manage everything
    // We'll store the wrapped block in the C registry and return a special marker
    return unsafeBitCast(wrappedBlock, to: UnsafeRawPointer.self)
}


#endif

// Note: The swift_async_hooks_install function is now provided by the DispatchInterpose target
// with appropriate implementations for each platform (Darwin vs non-Darwin)
