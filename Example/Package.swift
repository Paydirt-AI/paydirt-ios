// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaydirtExample",
    platforms: [.iOS(.v15)],
    products: [
        .executable(name: "PaydirtExample", targets: ["PaydirtExample"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "PaydirtExample",
            dependencies: [
                .product(name: "Paydirt", package: "ios-sdk")
            ],
            path: "."
        )
    ]
)
