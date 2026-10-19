// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskManager",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TaskManager",
            path: "Sources/TaskManager",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("Security"),
            ]
        ),
    ]
)
