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
// Linux: Provide container access functions for C code
@_cdecl("get_current_container")
public func get_current_container() -> UnsafeMutableRawPointer? {
    print("🔍 get_current_container() called from C code!")
    return Unmanaged.passUnretained(Container.current).toOpaque()
}

@_cdecl("set_current_container")
public func set_current_container(_ containerPtr: UnsafeMutableRawPointer?) {
    print("🔧 set_current_container() called from C code with pointer: \(String(describing: containerPtr))")
    guard let containerPtr = containerPtr else { return }
    let container = Unmanaged<Container>.fromOpaque(containerPtr).takeUnretainedValue()
    print("🔧 Container type: \(type(of: container))")
    // For now, just print - we'll implement the actual setting later
}
#endif

// Note: The swift_async_hooks_install function is now provided by the DispatchInterpose target
// with appropriate implementations for each platform (Darwin vs non-Darwin)
