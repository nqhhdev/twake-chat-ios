// swift-tools-version: 6.2
// Not a feature. Each feature is its own package in Packages/Features/<Feature> (ADR 0005), and the app links them
// one by one. This manifest only lists them, so that a tool walking Packages/*/ can run
// `swift build --package-path Packages/Features` and build every feature for the simulator.
import PackageDescription

let package = Package(
  name: "Features",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "Features", targets: ["Features"])
  ],
  dependencies: [
    .package(path: "Authentication"),
    .package(path: "ChatList"),
  ],
  targets: [
    .target(
      name: "Features",
      dependencies: [
        .product(name: "Authentication", package: "Authentication"),
        .product(name: "ChatList", package: "ChatList"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    )
  ]
)
