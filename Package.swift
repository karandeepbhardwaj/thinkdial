// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkDial",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ThinkDialCore", targets: ["ThinkDialCore"])
    ],
    targets: [
        .target(name: "ThinkDialCore"),
        .testTarget(name: "ThinkDialCoreTests", dependencies: ["ThinkDialCore"])
    ],
    swiftLanguageVersions: [.v5]
)
