# Knowledge Base Update Log

## 2026-11-11
* **Creation**: First draft of the architecture, eleven ADRs, constraints, workflows and glossary, written before any app code exists. Every page is a draft awaiting the project owner's review.
* **Decision**: The app reuses the Flutter app's bundle identifier (ADR 0012); the bundle identifier backlog item is closed and ADRs 0007, 0008, 0009 are updated to match. The project owner also accepted ADR 0012's first-launch cleanup and release rule.
* **Decision**: The project owner accepted ADRs 0001 and 0004 to 0010 as written. Pages stay `status: draft` until code exists to check them against.
* **Decision**: The project owner accepted the remaining rules in ADR 0002 (version checks only in DesignSystem) and ADR 0003 (exact SDK version pinning). All twelve ADRs are accepted.

## 2026-11-12
* **Decision**: Recorded the project owner's answers to TWAK-37 and TWAK-38 as ADR 0014 (GitHub Actions on GitHub-hosted macOS runners, swift-format) and ADR 0015 (pin matrix-rust-components-swift at exactly 26.04.01, filling in ADR 0003). Build and Open Verifications now point to ADR 0014; the snapshot tool and crash reporting stay open (TWAK-45).
* **Change**: Added `.swift-format` (swift-format defaults, unchanged) and `scripts/lint.sh` (lint, `--fix` to format) per ADR 0014 (TWAK-46). Build lists the commands. No Swift code existed yet, so nothing was reformatted.
* **Change**: Build lists `scripts/tests/lint_test.sh`, the test of `scripts/lint.sh` (TWAK-46). `Packages/` does not exist yet (TWAK-34 has not added code), so the package build/test loop has nothing to run.
