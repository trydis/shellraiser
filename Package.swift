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
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Carbon")
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "ghostty/macos/GhosttyKit.xcframework"
        )
    ]
)
