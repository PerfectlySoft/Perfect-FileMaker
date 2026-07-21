// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerfectFileMaker",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PerfectFileMaker", targets: ["PerfectFileMaker"]),
    ],
    dependencies: [
        .package(url: "https://github.com/taplin/Perfect-XML.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "PerfectFileMaker",
            dependencies: [
                .product(name: "PerfectXML", package: "Perfect-XML"),
            ]
        ),
        .testTarget(
            name: "PerfectFileMakerTests",
            dependencies: ["PerfectFileMaker"]
        ),
    ]
)
