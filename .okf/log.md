# Knowledge Base Update Log

## 2026-11-11
* **Creation**: First draft of the architecture, eleven ADRs, constraints, workflows and glossary, written before any app code exists. Every page is a draft awaiting the project owner's review.
* **Decision**: The app reuses the Flutter app's bundle identifier (ADR 0012); the bundle identifier backlog item is closed and ADRs 0007, 0008, 0009 are updated to match. The project owner also accepted ADR 0012's first-launch cleanup and release rule.
* **Decision**: The project owner accepted ADRs 0001 and 0004 to 0010 as written. Pages stay `status: draft` until code exists to check them against.
* **Decision**: The project owner accepted the remaining rules in ADR 0002 (version checks only in DesignSystem) and ADR 0003 (exact SDK version pinning). All twelve ADRs are accepted.

## 2026-11-12
* **Build**: The repository has an Xcode project: the `TwakeChat` app target (empty root view) and the `Domain`, `AppShared`, `DesignSystem` and `MatrixData` local packages wired as ADR 0005 says (TWAK-34). The Build page now lists the real commands and settings. The App and Constraints pages now say which parts exist.
* **Build**: The app build failed because Xcode passed `-suppress-warnings` to the local packages, which conflicts with their warnings-as-errors setting (TWAK-34). Each package folder is now also a folder reference in the project, so Xcode builds them as project packages and their warnings fail the app build. The Build page records this and the `LM_SKIP_METADATA_EXTRACTION` setting.
* **Build**: The Build page no longer lists an iOS 18 build command or asks for an iOS 18 simulator runtime: builds, tests and launches run on iOS 26 only (owner decision 2026-11-12, TWAK-34). The deployment target stays 18.0 as ADR 0002 says until the owner supersedes it.
