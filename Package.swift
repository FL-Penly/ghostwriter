// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GhostwriterApp",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "Packages/GhostwriterKit"),
        // KeyboardShortcuts 3.1.0 with its macros written out, since the Command Line Tools have no macro plugins.
        .package(path: "Vendor/KeyboardShortcuts"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Ghostwriter",
            dependencies: [
                .product(name: "GWCore", package: "GhostwriterKit"),
                .product(name: "Inference", package: "GhostwriterKit"),
                .product(name: "Prompting", package: "GhostwriterKit"),
                .product(name: "Memory", package: "GhostwriterKit"),
                .product(name: "Capture", package: "GhostwriterKit"),
                .product(name: "Input", package: "GhostwriterKit"),
                .product(name: "Overlay", package: "GhostwriterKit"),
                .product(name: "ScreenContext", package: "GhostwriterKit"),
                .product(name: "Actions", package: "GhostwriterKit"),
                .product(name: "Proofing", package: "GhostwriterKit"),
                .product(name: "CotypistImport", package: "GhostwriterKit"),
                "KeyboardShortcuts",
                "Sparkle",
            ],
            path: "Ghostwriter",
            exclude: ["Info.plist", "Ghostwriter.entitlements", "Assets.xcassets", "AppIcon.icon"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .unsafeFlags(["-Onone"]),
            ]
        ),
    ]
)
