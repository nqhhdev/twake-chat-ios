// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "MatrixData",
  platforms: [.iOS(.v18)],
  products: [.library(name: "MatrixData", targets: ["MatrixData"])],
  dependencies: [
    .package(path: "../Domain"),
    .package(path: "../AppShared"),
    .package(
      url: "https://github.com/matrix-org/matrix-rust-components-swift",
      exact: "26.04.01"
    ),
  ],
  targets: [
    .target(
      name: "MatrixData",
      dependencies: [
        "Domain",
        "AppShared",
        .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
      ]
    )
  ]
)
