// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Settings",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "Settings", targets: ["Settings"]),
    .library(name: "SettingsTestSupport", targets: ["SettingsTestSupport"]),
  ],
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "Settings",
      dependencies: [
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .target(
      name: "SettingsTestSupport",
      dependencies: [.product(name: "Domain", package: "Domain")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "SettingsTests",
      dependencies: [
        "Settings", "SettingsTestSupport",
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
