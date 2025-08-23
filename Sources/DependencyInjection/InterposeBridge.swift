//
//  InterposeBridge.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

import Foundation
import DispatchInterpose // the C target

@_cdecl("transformBlock")
func transformBlock(block: @escaping @convention(block) () -> Void) -> @convention(block) () -> Void {
    let container = Container.current
    return {
        withContainer(container) {
            block()
        }
    }
}
