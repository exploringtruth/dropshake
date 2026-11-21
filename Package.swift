// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dropshake",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Dropshake", targets: ["DropshakeApp"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0")
    ],
    targets: [
        .executableTarget(
            name: "DropshakeApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/DropshakeApp",
            resources: [.process("Resources")],
            linkerSettings: [
                // SwiftPM places linked binary frameworks beside `swift run`'s
                // executable. The packaged app also embeds Sparkle in
                // Contents/Frameworks, so support both launch locations.
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
