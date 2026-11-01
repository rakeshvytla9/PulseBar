// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PulseBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PulseBar", targets: ["PulseBar"])],
    targets: [.executableTarget(name: "PulseBar")]
)
