// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Domain",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "Domain", targets: ["Domain"])],
  dependencies: [],
  targets: [
    .target(name: "Domain"),
    .testTarget(name: "DomainTests", dependencies: ["Domain"]),
  ]
)
