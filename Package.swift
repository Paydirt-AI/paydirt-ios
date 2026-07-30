// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Paydirt",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Paydirt",
            targets: ["Paydirt"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Paydirt",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
