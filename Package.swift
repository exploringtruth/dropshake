// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Dropshake",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Dropshake", targets: ["DropshakeApp"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "DropshakeApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/DropshakeApp",
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
    ]
)
