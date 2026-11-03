// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ioskit",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "IOSKit", targets: ["IOSKit"]),
        .library(name: "IOSKitUI", targets: ["IOSKitUI"]),
        .library(name: "IOSKitWeb", targets: ["IOSKitWeb"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        .target(name: "IOSKit"),
        .target(
            name: "IOSKitUI",
            dependencies: [
                "IOSKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .target(name: "IOSKitWeb"),
        .testTarget(name: "IOSKitTests", dependencies: ["IOSKit", "IOSKitWeb"]),
    ]
)
