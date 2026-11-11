# Knowledge Base Update Log

## 2026-11-11
* **Creation**: First draft of the architecture, eleven ADRs, constraints, workflows and glossary, written before any app code exists. Every page is a draft awaiting the project owner's review.
* **Decision**: The app reuses the Flutter app's bundle identifier (ADR 0012); the bundle identifier backlog item is closed and ADRs 0007, 0008, 0009 are updated to match. The project owner also accepted ADR 0012's first-launch cleanup and release rule.
* **Decision**: The project owner accepted ADRs 0001 and 0004 to 0010 as written. Pages stay `status: draft` until code exists to check them against.
* **Decision**: The project owner accepted the remaining rules in ADR 0002 (version checks only in DesignSystem) and ADR 0003 (exact SDK version pinning). All twelve ADRs are accepted.
* **Proposal**: ADR 0013 (Proposed) pins the Flutter baseline to `twake-on-matrix` `5a3e9e84920078d3d0fb5148146a179c1a06c04a` on `origin/main` and gives each Flutter feature a status; Deferred Features gains the rows the inventory named and the page lacked. Waits for the project owner.
