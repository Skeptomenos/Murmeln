// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mrml",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mrml", targets: ["mrml"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.16.0")
    ],
    targets: [
        .executableTarget(
            name: "mrml",
            dependencies: [
                "WhisperKit"
            ],
            path: "Sources",
            resources: [.copy("Resources/cohere_bridge.py")]
        ),
        .testTarget(
            name: "MurmelnTests",
            dependencies: ["mrml"],
            path: "Tests"
        )
    ]
)
