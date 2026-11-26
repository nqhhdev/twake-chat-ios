// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Room",
  defaultLocalization: "en",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "Room", targets: ["Room"]),
    .library(name: "RoomTestSupport", targets: ["RoomTestSupport"]),
  ],
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "Room",
      dependencies: [
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      resources: [.process("Localizable.xcstrings")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .target(
      name: "RoomTestSupport",
      dependencies: [.product(name: "Domain", package: "Domain")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "RoomTests",
      dependencies: [
        "Room", "RoomTestSupport",
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
