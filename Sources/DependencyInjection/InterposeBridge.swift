//
//  InterposeBridge.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

import Foundation

@_cdecl("transformBlock")
func transformBlock(block: @escaping @convention(block) () -> Void) -> @convention(block) () -> Void {
    let container = Container.current
    return {
        withContainer(container) {
            block()
        }
    }
}

#if canImport(Darwin)
// Darwin implementation - DispatchInterpose is available
#else
// Non-Darwin implementation - provide stub
@_cdecl("swift_async_hooks_install")
func swift_async_hooks_install() {
    // No-op on non-Darwin platforms
}
#endif
