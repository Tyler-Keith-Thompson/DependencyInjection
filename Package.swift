// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "DependencyInjection",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
        .tvOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DependencyInjection",
            targets: ["DependencyInjection", "DependencyInjectionMacros"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-service-context", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"700.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.6.3"),
    ],
    targets: [
        // Macro implementation that performs the source transformations.
        .macro(
            name: "DependencyInjectionMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "DependencyInjection",
            dependencies: [
                "DependencyInjectionMacros",
                "DispatchInterpose",
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
            ]
        ),
        .target(
            name: "DispatchInterpose",
            publicHeadersPath: "Include"
        ),
        .testTarget(
            name: "DependencyInjectionTests",
            dependencies: [
                "DependencyInjection",
                "DependencyInjectionMacros",
                "DispatchInterpose",
            ]
        ),
        .testTarget(name: "DependencyInjectionMacrosTests",
                   dependencies: [
                    "DependencyInjectionMacros",
                    .product(name: "MacroTesting", package: "swift-macro-testing"),
                   ]
        ),
    ],
    swiftLanguageModes: [.version("6")]
)
