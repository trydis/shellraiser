// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shellraiser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Shellraiser",
            targets: ["Shellraiser"]
        )
    ],
    targets: [
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
        .testTarget(
            name: "ShellraiserTests",
            dependencies: [
                "Shellraiser"
            ],
            path: "Tests/ShellraiserTests"
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "ghostty/macos/GhosttyKit.xcframework"
        )
    ]
)
