// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppShared",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AppShared", targets: ["AppShared"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppShared",
            dependencies: [],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
