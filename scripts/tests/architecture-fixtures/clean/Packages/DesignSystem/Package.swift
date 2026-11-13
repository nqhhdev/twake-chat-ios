// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DesignSystem",
  platforms: [.iOS(.v18)],
  products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
  dependencies: [
    .package(url: "https://example.com/snapshot-library.git", from: "1.0.0")
  ],
  targets: [.target(name: "DesignSystem")]
)
