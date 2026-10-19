// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PasketCore",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "PasketCore",
            path: "pasket",
            exclude: ["ApplicationController.swift", "ContentView.swift", "MyApp.swift",
                      "ShortcutSettingsView.swift", "Assets.xcassets", "pasket.entitlements"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "PasketCoreTests", dependencies: ["PasketCore"],
                    swiftSettings: [.defaultIsolation(MainActor.self)])
    ],
    swiftLanguageModes: [.v5]
)
