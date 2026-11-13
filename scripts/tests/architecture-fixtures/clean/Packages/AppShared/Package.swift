// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "AppShared",
  products: [.library(name: "AppShared", targets: ["AppShared"])],
  targets: [.target(name: "AppShared")]
)
