// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Paydirt",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "Paydirt",
            targets: ["Paydirt"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "Paydirt",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios")
            ]
        ),
    ]
)
