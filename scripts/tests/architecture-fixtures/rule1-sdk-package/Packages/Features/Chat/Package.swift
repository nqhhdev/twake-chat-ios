// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Chat",
  dependencies: [
    .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.04.01")
  ],
  targets: [.target(name: "Chat")]
)
