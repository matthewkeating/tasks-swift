// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tasks",
    platforms: [
        .macOS(.v14) // Defines the app as macOS-only and sets the minimum framework version
    ],
    // Top-level packages this project fetches from remote sources
    dependencies: [
        // GoogleSignIn-iOS provides OAuth sign-in and access tokens for Google APIs
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "8.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Tasks",
            // Makes the fetched packages available to import inside this target's source files
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ],
            exclude: ["Info.plist"],
            resources: [
                .copy("AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "TasksTests",
            dependencies: ["Tasks"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
