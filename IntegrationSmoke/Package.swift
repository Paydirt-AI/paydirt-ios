// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaydirtIntegrationSmoke",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PaydirtIntegrationSmoke", targets: ["PaydirtIntegrationSmoke"]),
    ],
    dependencies: [
        .package(name: "paydirt-sdk", path: ".."),
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", exact: "5.81.3"),
        .package(url: "https://github.com/superwall/Superwall-iOS.git", exact: "4.16.1"),
    ],
    targets: [
        .target(
            name: "PaydirtIntegrationSmoke",
            dependencies: [
                .product(name: "Paydirt", package: "paydirt-sdk"),
                .product(name: "RevenueCat", package: "purchases-ios"),
                .product(name: "SuperwallKit", package: "Superwall-iOS"),
            ]
        ),
    ]
)
