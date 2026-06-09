// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notiful",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "NotifulCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Notiful",
            dependencies: ["NotifulCore"]
        ),
        // Dependency-free test runner (XCTest is unavailable with Command Line Tools only).
        // Run with: swift run NotifulTests
        .executableTarget(
            name: "NotifulTests",
            dependencies: ["NotifulCore"]
        ),
        // Vendor-side tool: generate a key pair and sign perpetual licenses.
        // Run with: swift run NotifulLicense <keygen|sign|verify> …
        .executableTarget(
            name: "NotifulLicense",
            dependencies: ["NotifulCore"]
        ),
    ]
)
