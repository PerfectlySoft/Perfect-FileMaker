// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerfectFileMaker",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PerfectFileMaker", targets: ["PerfectFileMaker"]),
    ],
    dependencies: [
        .package(path: "../Perfect-XML"),
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
