// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DesignSystem",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "DesignSystem",
      dependencies: [],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "DesignSystemTests",
      dependencies: ["DesignSystem"],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
