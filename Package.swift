// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mrml",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "mrml", targets: ["mrml"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.16.0"),
        // Pinned exact: 0.15.5 shipped a breaking ModelHub change the day
        // before Phase 8 started — versions are not interchangeable.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5")
    ],
    targets: [
        .executableTarget(
            name: "mrml",
            dependencies: [
                "WhisperKit",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MurmelnTests",
            dependencies: ["mrml"],
            path: "Tests",
            exclude: ["PublicSplitPrivacyTests.sh"]
        )
    ]
)
