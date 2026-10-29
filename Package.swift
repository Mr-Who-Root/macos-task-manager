// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskManager",
    platforms: [.macOS(.v15)],
    targets: [
        // Code shared by the app and its widget extension (Foundation only).
        .target(
            name: "TaskManagerShared",
            path: "Sources/TaskManagerShared",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TaskManager",
            dependencies: ["TaskManagerShared"],
            path: "Sources/TaskManager",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("Security"),
                .linkedFramework("WidgetKit"),
            ]
        ),
        // Packaged by scripts/build-app.sh as Contents/PlugIns/TaskManagerWidgets.appex.
        .executableTarget(
            name: "TaskManagerWidgets",
            dependencies: ["TaskManagerShared"],
            path: "Sources/TaskManagerWidgets",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
