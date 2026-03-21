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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "mrml",
            dependencies: [
                "KeyboardShortcuts"
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MurmelnTests",
            dependencies: ["mrml"],
            path: "Tests"
        )
    ]
)
