// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ShellIsland",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ShellIslandCore",
            targets: ["ShellIslandCore"]
        ),
        .executable(
            name: "ShellIslandApp",
            targets: ["ShellIslandApp"]
        ),
        .executable(
            name: "ShellIslandHooks",
            targets: ["ShellIslandHooks"]
        ),
    ],
    targets: [
        .target(
            name: "ShellIslandCore"
        ),
        .executableTarget(
            name: "ShellIslandApp",
            dependencies: ["ShellIslandCore"]
        ),
        .executableTarget(
            name: "ShellIslandHooks",
            dependencies: []
        ),
        .testTarget(
            name: "ShellIslandCoreTests",
            dependencies: ["ShellIslandCore"]
        ),
        .testTarget(
            name: "ShellIslandAppTests",
            dependencies: ["ShellIslandApp", "ShellIslandCore"]
        ),
    ]
)
