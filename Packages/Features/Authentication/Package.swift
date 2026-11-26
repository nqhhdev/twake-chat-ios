// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Authentication",
  defaultLocalization: "en",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "Authentication", targets: ["Authentication"]),
    .library(name: "AuthenticationTestSupport", targets: ["AuthenticationTestSupport"]),
  ],
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "Authentication",
      dependencies: [
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      resources: [.process("Localizable.xcstrings")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .target(
      name: "AuthenticationTestSupport",
      dependencies: [.product(name: "Domain", package: "Domain")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "AuthenticationTests",
      dependencies: [
        "Authentication", "AuthenticationTestSupport",
        .product(name: "Domain", package: "Domain"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
