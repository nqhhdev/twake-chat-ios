// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DesignSystem",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "DesignSystem",
      dependencies: [],
      resources: [.process("Resources")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "DesignSystemTests",
      dependencies: ["DesignSystem"],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
