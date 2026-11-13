---
type: ADR
title: "ADR 0022: Lay out by the Flutter app's width breakpoints"
description: "Under 905 pt wide the app shows one column; from 905 pt the 472 pt chat list sits beside the chat, as twake-on-matrix ResponsiveUtils does, so phones, a folded and an unfolded Duo and iPads share one rule."
tags: [adr, ui, layout]
status: draft
---
# ADR 0022: Lay out by the Flutter app's width breakpoints

**Status:** Decided under the project owner's delegation, 2026-11-13, after the owner asked that the design "adapt
with Duo and another phone"; for the owner's review.

## Context
The app runs on phones, on the iPhone Duo (folded: a phone screen; unfolded: about 951 × 669 pt) and on iPads. The
Flutter app has one rule for all of them, in `lib/utils/responsive/responsive_utils.dart` and
`lib/widgets/layouts/adaptive_layout/app_adaptive_scaffold.dart`: under `minTabletWidth` (905) it shows one column;
from 905 the body (the chat list) is `bodyRadioWidth` (472) wide beside the secondary body (the chat). Message bubbles
are at most `messageBubbleDesktopMaxWidth` (520) or 0.88 of a narrow screen (`message_style.dart`). The width compared
is the whole screen (`MediaQuery`), safe areas included.

## Decision
- DesignSystem `TwakeLayout` holds these numbers; the app's `ChatShell` picks the layout from the window width with
  its safe areas, so folding, unfolding or rotating moves between the two layouts and keeps the open chat.
- One column: the chat is pushed over the chat list. Two columns: the 472 pt list, a 1 pt `surface` divider, the chat;
  with no chat open the right column shows the Twake logo.
- Sign-in screens keep at most 472 pt of width on a wide screen, centred, so their buttons do not span it.
- Bubbles hug their content up to `TwakeLayout.bubbleWidth(in:)`.

## Consequences
**Good.** One rule, the Flutter one, for every device; nothing Duo-specific. **Costly.** SwiftUI gives the width
without safe areas, so the shell adds them back to match Flutter. **Open:** the split is fixed at 472 pt and not
resizable; the Flutter desktop's third column (chat details) is not built yet.
