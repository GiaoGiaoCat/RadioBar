// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "RadioBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RadioBar", targets: ["RadioBar"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "RadioBar", dependencies: [.product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/stations.default.json"), .copy("Generated/builtin-streams.bin")])]
)
