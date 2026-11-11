---
type: Workflow
title: "Build"
description: "How the project will be built and checked; commands are planned until the Xcode project exists."
tags: [build, ci]
status: draft
---
# Build

> Not runnable yet: the repository has no Xcode project. Replace this page with the real commands when it is created.

## Planned
| Step | Tool |
|---|---|
| Resolve dependencies | Swift Package Manager through Xcode; `Package.resolved` is committed |
| Build the app | `xcodebuild` for the `TwakeChat` scheme, on an iOS 26 simulator and an iOS 18 simulator |
| Build one package alone | `swift build` inside `Packages/<Name>` where the package has no iOS-only dependency, otherwise `xcodebuild` |
| Format and lint | Not chosen (swift-format or SwiftLint) |
| Release build and signing | Not designed; the Flutter app uses fastlane |

## Requirements
- Xcode with the iOS 26 SDK, and an iOS 18 simulator runtime installed.
