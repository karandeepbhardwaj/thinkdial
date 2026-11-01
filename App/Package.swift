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
            name: "ThinkDialDDCSupport",
            path: "Sources/ThinkDialDDCSupport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreDisplay"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ThinkDial",
            dependencies: [
                "ThinkDialDDCSupport",
                .product(name: "ThinkDialCore", package: "ThinkDial"),
                .product(name: "AppleSiliconDDC", package: "AppleSiliconDDC")
            ],
            path: "Sources/ThinkDial",
            linkerSettings: [
                .linkedFramework("CoreDisplay"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
