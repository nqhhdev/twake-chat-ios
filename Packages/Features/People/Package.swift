// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "People",
  defaultLocalization: "en",
  platforms: [.iOS(.v18)],
  products: [
    .library(name: "People", targets: ["People"]),
    .library(name: "PeopleTestSupport", targets: ["PeopleTestSupport"]),
  ],
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "People",
      dependencies: [
        .product(name: "Domain", package: "Domain"),
        .product(name: "DesignSystem", package: "DesignSystem"),
      ],
      resources: [.process("Localizable.xcstrings")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .target(
      name: "PeopleTestSupport",
      dependencies: [.product(name: "Domain", package: "Domain")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "PeopleTests",
      dependencies: [
        "People", "PeopleTestSupport",
        .product(name: "Domain", package: "Domain"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
