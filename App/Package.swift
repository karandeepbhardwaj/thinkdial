// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkDialApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ThinkDial", targets: ["ThinkDial"])
    ],
    dependencies: [
        .package(path: ".."),
        // No tagged release. This is the main commit that fixed the package build.
        .package(url: "https://github.com/waydabber/AppleSiliconDDC.git", revision: "67ff964ab8123d9d35fadf7d8e1a7c677d31da14")
    ],
    targets: [
        .target(
            name: "ThinkDialI2C",
            path: "Sources/ThinkDialI2C",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "ThinkDial",
            dependencies: [
                "ThinkDialI2C",
                .product(name: "ThinkDialCore", package: "ThinkDial"),
                .product(name: "AppleSiliconDDC", package: "AppleSiliconDDC")
            ],
            path: "Sources/ThinkDial"
        )
    ],
    swiftLanguageVersions: [.v5]
)
