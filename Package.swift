// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BlinkCore", platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "BlinkCore", targets: ["BlinkCore"])],
    targets: [.target(name: "BlinkCore"), .testTarget(name: "BlinkCoreTests", dependencies: ["BlinkCore"])])
