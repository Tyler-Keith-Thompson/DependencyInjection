//
//  ResolvedOutsideContainerMessageTests.swift
//  DependencyInjection
//

import Testing
@testable import DependencyInjection

struct ResolvedOutsideContainerMessageTests {
    @Test func namesBothCausesAndTheOpenTestContainer() {
        let containerLine: UInt = #line + 1
        withTestContainer {
            let message = resolvedOutsideContainerMessage(dependency: Int.self, file: "Caller.swift", line: 7, function: "caller()")
            #expect(message.contains("Tried to resolve Int outside any container, called from Caller.swift:7 in caller()"))
            #expect(message.contains("doesn't use withTestContainer"))
            #expect(message.contains("Work escaped its container"))
            #expect(message.contains("a request handler a server framework (Vapor, SwiftNIO) runs on its own event-loop task"))
            #expect(message.contains("\(#file):\(containerLine) in \(#function)"))
        }
    }

    @Test func listsEveryOpenTestContainerIncludingNestedOnes() async {
        let outerLine: UInt = #line + 1
        await withTestContainer {
            let innerLine: UInt = #line + 1
            withTestContainer {
                let message = resolvedOutsideContainerMessage(dependency: String.self, file: "f", line: 1, function: "g")
                #expect(message.contains("\(#file):\(outerLine) in \(#function)"))
                #expect(message.contains("\(#file):\(innerLine) in \(#function)"))
            }
        }
    }

    @Test func closedTestContainersAreNoLongerListed() {
        let line: UInt = #line + 1
        withTestContainer { }
        let message = resolvedOutsideContainerMessage(dependency: Int.self, file: "f", line: 1, function: "g")
        #expect(!message.contains("\(#file):\(line) in \(#function)"))
    }
}
