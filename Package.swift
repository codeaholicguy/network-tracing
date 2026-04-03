// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkTracer",
    platforms: [.macOS(.v13)],
    targets: [
        // Core library — testable, no AppKit/UI dependencies
        .target(
            name: "NetworkTracerCore",
            path: "Sources/NetworkTracerCore"
        ),
        // App executable — menubar UI
        .executableTarget(
            name: "NetworkTracer",
            dependencies: ["NetworkTracerCore"],
            path: "Sources/NetworkTracer"
        ),
        .testTarget(
            name: "NetworkTracerTests",
            dependencies: ["NetworkTracerCore"],
            path: "Tests/NetworkTracerTests"
        )
    ]
)
