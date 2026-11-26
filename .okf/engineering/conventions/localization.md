---
type: Convention
title: "Localization"
description: "Every user-facing string goes through the package's localized() helper and its Localizable.xcstrings, in English, French and Vietnamese, checked by a test per package."
tags: [localization, strings, l10n]
status: draft
---
# Localization

#90. English is the source language; French and Vietnamese are filled for every key.

| Rule | How |
|---|---|
| Where strings live | Each package that shows text has `Sources/<Target>/Localizable.xcstrings`, declared as a resource, and `defaultLocalization: "en"` in its `Package.swift` |
| How code reads them | `localized("Sign in")` from the package's `Localization.swift`, which reads `Bundle.module`. SwiftUI's `Text("…")` alone would look in the app bundle, so a literal never goes to a view without `localized` |
| Keys | The English text itself, so the code stays readable and the key is stable while the English does not change. Changing the English is a new key |
| Interpolation | `localized("\(count) members")`; the catalog key uses the format the compiler gives (`%lld` for integers, `%@` for strings) |
| Plurals | One key with the catalog's plural variations: `one` and `other` for English and French, `other` for Vietnamese |
| Dates and numbers | `Date.formatted`, `formatted()` and `ListFormatter`, never words joined by hand |
| Wording | French and Vietnamese take the wording of twake-on-matrix's `assets/l10n/intl_fr.arb` and `intl_vi.arb` where the English is the same, so both apps say the same thing; an ARB value that is wrong is overridden and kept in the catalog |
| Check | `Tests/<Target>Tests/LocalizationTests.swift` reads the `localized("…")` keys of the package's sources and fails when one has no French or Vietnamese value in the compiled tables. Domain and DesignSystem read `Localizable.xcstrings` itself: `swift test` on Xcode 26.6 copies a catalog without compiling it, and an incremental Xcode build can copy DesignSystem's bundle with empty `.lproj` folders. MatrixData's test is in `Tests/MatrixDataTests` and turns each `\(…)` into `%@`, since all of its interpolations are strings |
| Lint | `scripts/check-localization.sh` (CI `architecture` job) fails on a SwiftUI view or modifier in `Packages/**/Sources` that takes a bare literal with a letter in it (`Text("Save")`, `Button("Edit", systemImage:)`, `.accessibilityLabel("Close")`, `prompt: "Search"`). Text with no words, or a brand name, uses `Text(verbatim:)`. `#Preview` code is not checked |
| App target | `TwakeChat/Localizable.xcstrings`. A bare `Text("…")` in the app reads the main bundle, so it is enough there; plain `String` values use `String(localized:)`. The catalog also holds the push `loc-key` `newMessageInTwake`. `knownRegions` lists `en`, `fr` and `vi`, so `Bundle.main.localizations` lets the system language and the server's common-settings language pick Vietnamese. `AppLocalizationTests` checks it |
| Extensions | The NSE shows MatrixData's notification bodies, and its `.appex` embeds `MatrixData_MatrixData.bundle`. The Share extension has no text of its own |
| Not localized | Text that goes over the wire to other clients (the poll-end fallback `The poll has ended.`), device names other devices see (`Twake Chat on iPhone`), logs and internal errors |
