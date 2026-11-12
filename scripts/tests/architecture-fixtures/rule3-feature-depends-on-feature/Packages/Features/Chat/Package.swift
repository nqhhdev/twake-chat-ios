// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Chat",
  dependencies: [
    .package(path: "../../Domain"),
    .package(path: "../Login"),
  ],
  targets: [.target(name: "Chat", dependencies: ["Domain", "Login"])]
)
