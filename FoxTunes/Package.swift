// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoxTunes",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "FoxTunes", targets: ["FoxTunes"]),
    ],
    targets: [
        .target(
            name: "JellyfinAPI",
            path: "JellyfinAPI"
        ),
        .target(
            name: "AudioEngine",
            path: "AudioEngine"
        ),
        .executableTarget(
            name: "FoxTunes",
            dependencies: ["JellyfinAPI", "AudioEngine"],
            path: "FoxTunes"
        ),
        .testTarget(
            name: "JellyfinAPITests",
            dependencies: ["JellyfinAPI"],
            path: "Tests/JellyfinAPITests"
        ),
        .testTarget(
            name: "AudioEngineTests",
            dependencies: ["AudioEngine"],
            path: "Tests/AudioEngineTests"
        ),
    ]
)
