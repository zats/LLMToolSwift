// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "LLMToolSwift",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LLMToolSwift",
            targets: ["LLMToolSwift"]
        ),
        .library(
            name: "LLMToolOpenAI",
            targets: ["LLMToolOpenAI"]
        ),
    ],
    dependencies: [
        // SwiftSyntax must match the Swift toolchain series.
        // Targeting Swift 6.0 compatibility: use the 6.0 release branch.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", branch: "release/6.0"),
        .package(url: "https://github.com/MacPaw/OpenAI", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "LLMToolSwiftMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(
            name: "LLMToolSwift",
            dependencies: ["LLMToolSwiftMacros"],
            swiftSettings: [
                // Enable library evolution so downstream SDKs built "for distribution" are compatible
                .unsafeFlags(["-enable-library-evolution"])
            ]
        ),

        // Optional integration target for the OpenAI client types.
        .target(
            name: "LLMToolOpenAI",
            dependencies: [
                "LLMToolSwift",
                .product(name: "OpenAI", package: "OpenAI")
            ]
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "LLMToolSwiftTests",
            dependencies: [
                "LLMToolSwiftMacros",
                "LLMToolSwift",
                "LLMToolOpenAI",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
    ,
    swiftLanguageVersions: [.v6]
)
