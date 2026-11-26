// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Domain",
  defaultLocalization: "en",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "Domain", targets: ["Domain"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "Domain",
      dependencies: [],
      resources: [.process("Localizable.xcstrings")],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
    .testTarget(
      name: "DomainTests",
      dependencies: ["Domain"],
      swiftSettings: [.treatAllWarnings(as: .error)]
    ),
  ]
)
