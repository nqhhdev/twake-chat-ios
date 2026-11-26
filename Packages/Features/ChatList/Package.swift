// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ChatList",
  defaultLocalization: "en",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "ChatList", targets: ["ChatList"]),
    .library(name: "ChatListTestSupport", targets: ["ChatListTestSupport"]),
  ],
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "ChatList",
      dependencies: [
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      resources: [.process("Localizable.xcstrings")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .target(
      name: "ChatListTestSupport",
      dependencies: [.product(name: "Domain", package: "Domain")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "ChatListTests",
      dependencies: [
        "ChatList", "ChatListTestSupport",
        .product(name: "Domain", package: "Domain"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
