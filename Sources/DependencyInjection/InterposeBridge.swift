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
    
    withContainer(container) {
        originalWork(context)
    }
}

// Linux: Get current container for C code
@_cdecl("getCurrentContainer")
public func getCurrentContainer() -> UnsafeMutableRawPointer? {
    print("🔍 getCurrentContainer() called from C code!")
    return Unmanaged.passUnretained(Container.current).toOpaque()
}
#endif

// Note: The swift_async_hooks_install function is now provided by the DispatchInterpose target
// with appropriate implementations for each platform (Darwin vs non-Darwin)
