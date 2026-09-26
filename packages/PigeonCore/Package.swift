// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PigeonCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "PigeonCore", targets: ["PigeonCore"])],
    targets: [.target(name: "PigeonCore"), .testTarget(name: "PigeonCoreTests", dependencies: ["PigeonCore"])]
)
