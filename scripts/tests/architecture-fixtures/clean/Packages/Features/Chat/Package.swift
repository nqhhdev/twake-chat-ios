// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Chat",
  platforms: [.iOS(.v18)],
  products: [.library(name: "Chat", targets: ["Chat"])],
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [.target(name: "Chat", dependencies: ["Domain", "DesignSystem"])]
)
