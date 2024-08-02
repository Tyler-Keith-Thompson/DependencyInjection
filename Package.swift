// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DependencyInjection",
    platforms: [.macOS(.v10_15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DependencyInjection",
            targets: ["DependencyInjection"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-service-context", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DependencyInjection",
            dependencies: [
                .product(name: "ServiceContextModule", package: "swift-service-context"),
            ]
        ),
        .testTarget(
            name: "DependencyInjectionTests",
            dependencies: [
                "DependencyInjection",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
