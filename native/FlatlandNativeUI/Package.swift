// swift-tools-version: 6.2

import PackageDescription

// The native user interface for Flatland (SwiftUI), loaded by Godot as a GDExtension.
// Godot calls into it (show_preferences...) and it calls back by emitting signals.
// See ../README.md.
let package = Package(
    name: "FlatlandNativeUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FlatlandNativeUI", type: .dynamic, targets: ["FlatlandNativeUI"]),
    ],
    dependencies: [
        // Pinned to a revision whose README says it supports Godot 4.7.
        .package(url: "https://github.com/migueldeicaza/SwiftGodot",
                 revision: "9aa1f47863f4f4e3fdd8fe72275725739575d6cb"),
    ],
    targets: [
        .target(
            name: "FlatlandNativeUI",
            dependencies: [
                .product(name: "SwiftGodotRuntimeStatic", package: "SwiftGodot"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
