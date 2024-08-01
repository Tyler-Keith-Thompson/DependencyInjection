//
//  ContainerKey.swift
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/1/24.
//

public protocol ContainerKey {
    associatedtype Value
    static var defaultValue: Value { get }
}
