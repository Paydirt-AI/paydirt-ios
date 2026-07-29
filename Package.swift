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
    dependencies: [
        // RevenueCat's supported SwiftPM mirror. Using the same package identity
        // as host apps prevents duplicate RevenueCat module graphs.
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "Paydirt",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios-spm")
            ],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
