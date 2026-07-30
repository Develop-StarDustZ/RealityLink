// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RealityLink",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RealityLink", targets: ["RealityLink"])
    ],
    targets: [
        .executableTarget(
            name: "RealityLink",
            path: "Sources/RealityLink"
        ),
        .testTarget(
            name: "RealityLinkTests",
            dependencies: ["RealityLink"],
            path: "Tests/RealityLinkTests"
        )
    ]
)
