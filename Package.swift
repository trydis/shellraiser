// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shellraiser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ShellraiserShimKit",
            targets: ["ShellraiserShimKit"]
        ),
        .executable(
            name: "Shellraiser",
            targets: ["Shellraiser"]
        ),
        .executable(
            name: "shellraiserctl",
            targets: ["shellraiserctl"]
        ),
        .executable(
            name: "tmux",
            targets: ["tmux"]
        )
    ],
    targets: [
        .target(
            name: "ShellraiserShimKit",
            path: "Sources/ShellraiserShimKit"
        ),
        .executableTarget(
            name: "Shellraiser",
            dependencies: [
                "GhosttyKit"
            ],
            path: "Sources/Shellraiser",
            resources: [
                .copy("Infrastructure/AppleScript/ShellraiserScripting.xml")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "shellraiserctl",
            dependencies: [
                "ShellraiserShimKit"
            ],
            path: "Sources/shellraiserctl"
        ),
        .executableTarget(
            name: "tmux",
            dependencies: [
                "ShellraiserShimKit"
            ],
            path: "Sources/tmux"
        ),
        .testTarget(
            name: "ShellraiserTests",
            dependencies: [
                "Shellraiser"
            ],
            path: "Tests/ShellraiserTests"
        ),
        .testTarget(
            name: "ShellraiserShimKitTests",
            dependencies: [
                "ShellraiserShimKit"
            ],
            path: "Tests/ShellraiserShimKitTests"
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "ghostty/macos/GhosttyKit.xcframework"
        )
    ]
)
