// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MatrixData",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "MatrixData", targets: ["MatrixData"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../AppShared"),
    ],
    targets: [
        .target(
            name: "MatrixData",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "AppShared", package: "AppShared"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
