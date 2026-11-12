// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "MatrixData",
  dependencies: [
    .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", from: "26.04.01")
  ],
  targets: [.target(name: "MatrixData")]
)
