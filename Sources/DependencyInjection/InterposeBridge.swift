//
//  InterposeBridge.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

import Foundation

#if canImport(Darwin)
@_cdecl("di_transformBlock")
func transformBlock(block: @escaping @convention(block) () -> Void) -> @convention(block) () -> Void {
    let container = Container.current
    return {
        withContainer(container) {
            block()
        }
    }
}
#endif

// Note: The swift_async_hooks_install function is now provided by the DispatchInterpose target
// with appropriate implementations for each platform (Darwin vs non-Darwin)
