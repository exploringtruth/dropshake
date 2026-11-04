// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Dropshake",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Dropshake", targets: ["DropshakeApp"])],
    targets: [.executableTarget(name: "DropshakeApp", path: "Sources/DropshakeApp")]
)
