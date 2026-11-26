import DesignSystem
import Domain
import SwiftUI

/// What the timeline's scroll geometry reports, so one change handler can both follow the bottom and page at the top.
private struct TimelineScrollGeometry: Equatable {
  var isAtBottom: Bool
  var isNearTop: Bool
  /// The loaded content is shorter than the viewport, so a few pages may load to fill it.
  var isShort: Bool
}

/// The scrolling timeline. New messages spring in from the bottom and the view follows them while the user is at the
/// bottom; scrolled up, a button brings the user back down, as in Telegram and iMessage.
struct TimelineScroll: View {
  let viewModel: RoomViewModel
  let bubbleWidth: CGFloat
  let columnWidth: CGFloat

  @State private var position = ScrollPosition(idType: String.self, edge: .bottom)
  @State private var isAtBottom = true
  /// The newest row when the user scrolled up; what arrives after it is counted on the scroll-down button.
  @State private var lastSeenRowId: String?
  /// The row at the top of the viewport when a page was asked for, so a prepend keeps it there.
  @State private var paginationAnchorId: String?
  @State private var shownLastRowId: String?

  var body: some View {
    let rows = viewModel.rows
    let newCount = ChatRow.incomingCount(after: lastSeenRowId, in: rows)
    let animatesAppend = RoomMetrics.animatesAppend(
      previousLastId: shownLastRowId, rowIds: rows.map(\.id))
    ScrollView {
      LazyVStack(spacing: 0) {
        if let placeholder = viewModel.placeholder {
          // No message to show yet: say so in the middle of the screen instead of a small spinner at its top.
          TimelinePlaceholderView(placeholder: placeholder, bubbleWidth: bubbleWidth) {
            Task { await viewModel.resumeHistory() }
          }
          .task(id: placeholder) {
            if placeholder == .loading { await viewModel.loadOlderWhileVisible() }
          }
        } else if !viewModel.reachedStart {
          if viewModel.isHistoryPaused {
            // Loading stopped by itself (many pages with nothing to show, or pages failing): the user asks for more.
            Button(localized("Load earlier messages")) { Task { await viewModel.resumeHistory() } }
              .buttonStyle(.bordered)
              .padding()
          } else {
            // Visible only while a page the user asked for is in flight; it does not start further pages.
            ProgressView()
              .padding()
              .opacity(viewModel.isLoadingOlder ? 1 : 0)
          }
        }
        if viewModel.reachedStart, !rows.contains(where: Self.isMessage) {
          EmptyChatCardView(card: viewModel.emptyChatCard)
            .padding(.vertical, 24)
        }
        ForEach(rows) { row in
          ChatRowView(row: row, bubbleWidth: bubbleWidth, viewModel: viewModel)
            .frame(width: columnWidth, alignment: .leading)
            .transition(animatesAppend ? Self.insertion(for: row) : .identity)
        }
      }
      .padding(.horizontal, RoomMetrics.gutter)
      .padding(.vertical, 8)
      .animation(
        animatesAppend ? .spring(response: 0.38, dampingFraction: 0.78) : nil,
        value: rows.last?.id
      )
      .scrollTargetLayout()
      .frame(width: columnWidth + 2 * RoomMetrics.gutter, alignment: .leading)
    }
    .scrollPosition($position, anchor: RoomMetrics.topAnchor)
    .onChange(of: rows.last?.id, initial: true) { _, lastId in shownLastRowId = lastId }
    .onChange(of: viewModel.scrollTarget) { _, target in
      guard let target else { return }
      withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
        position.scrollTo(id: target, anchor: RoomMetrics.middleAnchor)
      }
      viewModel.scrollTarget = nil
    }
    // Reopened where it was left (issue #138): the same message at the top, without animation. `initial` because the
    // target is set with the first messages, before this view shows.
    .onChange(of: viewModel.restoreTarget, initial: true) { _, target in
      guard let target else { return }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        position.scrollTo(id: target, anchor: RoomMetrics.topAnchor)
      }
      viewModel.restoreTarget = nil
    }
    .onDisappear {
      viewModel.rememberScroll(
        isAtBottom: isAtBottom, topRowId: position.viewID(type: String.self))
    }
    // Open on the newest message, and stay on it as messages arrive or pictures load.
    .defaultScrollAnchor(RoomMetrics.bottomAnchor)
    // Pinning size changes to the bottom while scrolled up would drag the reader with new
    // messages or with a prepend; only the bottom of a chat they are already following stays put.
    .defaultScrollAnchor(isAtBottom ? RoomMetrics.bottomAnchor : nil, for: .sizeChanges)
    .scrollDismissesKeyboard(.interactively)
    .onScrollGeometryChange(for: TimelineScrollGeometry.self) { geometry in
      // The visible rect accounts for the insets (the composer, the safe area), unlike the bare content offset.
      TimelineScrollGeometry(
        isAtBottom: geometry.visibleRect.maxY >= geometry.contentSize.height - 80,
        isNearTop: geometry.contentOffset.y < 400,
        isShort: geometry.contentSize.height > 0
          && geometry.contentSize.height <= geometry.visibleRect.height + 8)
    } action: { _, geometry in
      lastSeenRowId = geometry.isAtBottom ? nil : viewModel.rows.last?.id
      withAnimation(.easeOut(duration: 0.2)) { isAtBottom = geometry.isAtBottom }
      if geometry.isShort, !viewModel.reachedStart, viewModel.placeholder == nil {
        Task { await viewModel.loadOlderWhileVisible() }
      } else if !geometry.isShort {
        if geometry.isNearTop {
          if paginationAnchorId == nil {
            paginationAnchorId =
              position.viewID(type: String.self) ?? viewModel.rows.first?.id
          }
        } else {
          paginationAnchorId = nil
        }
        Task { await viewModel.topZoneChanged(isNearTop: geometry.isNearTop) }
      }
    }
    .onChange(of: viewModel.rows) { old, new in
      restorePaginationAnchor(from: old, to: new)
    }
    // The SDK empties and refills a timeline after a gap in sync, and the keyboard resizes the view: either can leave
    // the scroll offset outside the new content, which shows as an empty screen until the user drags. Come back to
    // the newest message when nothing of the content is in view.
    .onScrollGeometryChange(for: Bool.self) { geometry in
      TimelineScroll.showsNothing(
        visible: geometry.visibleRect, contentHeight: geometry.contentSize.height)
    } action: { _, showsNothing in
      if showsNothing { position.scrollTo(edge: .bottom) }
    }
    // Sending brings the reader back to the newest message, as the Flutter chat does: the message they just wrote
    // shows even when they were reading older ones.
    .onChange(of: viewModel.sendCount) {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
        position.scrollTo(edge: .bottom)
      }
    }
    // A list replaced as a whole while the user is on the newest message stays on the newest message.
    .onChange(of: rows.first?.id) {
      if isAtBottom { position.scrollTo(edge: .bottom) }
    }
    .overlay(alignment: .bottomTrailing) {
      if !isAtBottom {
        Button {
          withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            position.scrollTo(edge: .bottom)
          }
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SysColors.primary)
            .frame(width: 40, height: 40)
            .background(SysColors.onPrimary, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .overlay(alignment: .top) {
              if newCount > 0 {
                Text(verbatim: newCount > 99 ? "99+" : "\(newCount)")
                  .textStyle(TextStyles.labelSmall)
                  .foregroundStyle(SysColors.onPrimary)
                  .padding(.horizontal, 6)
                  .frame(minWidth: 20, minHeight: 20)
                  .background(SysColors.primary, in: Capsule())
                  .offset(y: -10)
                  .contentTransition(.numericText())
                  .transition(.scale.combined(with: .opacity))
              }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: newCount)
        }
        .accessibilityLabel(
          newCount > 0
            ? localized("Scroll to the latest message, \(newCount) new")
            : localized("Scroll to the latest message")
        )
        .padding(16)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
      }
    }
  }

  /// Whether the viewport lies wholly above or below the content, so no row is in view.
  static func showsNothing(visible: CGRect, contentHeight: CGFloat) -> Bool {
    contentHeight > 0 && (visible.minY >= contentHeight || visible.maxY <= 0)
  }

  /// After older rows are prepended, put the message the user was looking at back at the top, without animation.
  private func restorePaginationAnchor(from old: [ChatRow], to new: [ChatRow]) {
    guard let id = paginationAnchorId, let oldIndex = old.firstIndex(where: { $0.id == id }),
      let newIndex = new.firstIndex(where: { $0.id == id }), newIndex > oldIndex
    else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { position.scrollTo(id: id, anchor: RoomMetrics.topAnchor) }
  }

  private static func isMessage(_ row: ChatRow) -> Bool {
    switch row {
    case .message, .album: true
    case .other, .notices: false
    }
  }

  /// A new bubble grows from its sender's side and rises a little; other rows fade in.
  private static func insertion(for row: ChatRow) -> AnyTransition {
    let isOwn: Bool? =
      switch row {
      case .message(let model): model.message.isOwn
      case .album(let model): model.messages.first?.isOwn
      case .other, .notices: nil
      }
    guard let isOwn else { return .opacity }
    return .asymmetric(
      insertion: .scale(scale: 0.85, anchor: isOwn ? .bottomTrailing : .bottomLeading)
        .combined(with: .offset(y: 12)).combined(with: .opacity),
      removal: .opacity.combined(with: .scale(scale: 0.9)))
  }
}

/// One row: a message, an album, or a divider or room event.
struct ChatRowView: View {
  let row: ChatRow
  let bubbleWidth: CGFloat
  let viewModel: RoomViewModel

  var body: some View {
    if viewModel.isSelectingMessages, let message = row.selectableMessage {
      SelectableRow(message: message, viewModel: viewModel) { content }
    } else {
      content
    }
  }

  @ViewBuilder private var content: some View {
    switch row {
    case .message(let model):
      MessageRow(
        message: model.message, position: model.position, isRead: model.isRead,
        bubbleWidth: bubbleWidth, viewModel: viewModel)
    case .album(let model):
      MessageRow(
        message: model.messages[model.messages.count - 1], position: model.position,
        isRead: model.isRead, bubbleWidth: bubbleWidth,
        viewModel: viewModel, album: model)
    case .other(let item):
      OtherRow(item: item)
    case .notices(let model):
      NoticesRow(model: model)
    }
  }
}

/// Room events in a row, folded as Element X and Messages fold them: a quiet capsule ("8 changes") that opens into
/// the list of events and closes again.
struct NoticesRow: View {
  let model: NoticesRowModel
  @State private var isOpen = false

  var body: some View {
    VStack(spacing: 4) {
      Button {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isOpen.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "info.circle")
          Text(isOpen ? localized("Hide changes") : localized("\(model.texts.count) changes"))
          Image(systemName: "chevron.down")
            .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(SysColors.textSecondary)
        .padding(.horizontal, RoomMetrics.capsuleInset)
        .padding(.vertical, 6)
        .background(SysColors.surface, in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityHint(
        isOpen ? localized("Hides the room changes") : localized("Shows the room changes"))
      if isOpen {
        ForEach(Array(model.texts.enumerated()), id: \.offset) { _, text in
          Text(text)
            .textStyle(TextStyles.bodySmall)
            .foregroundStyle(SysColors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
  }
}

/// A day divider or a room event.
struct OtherRow: View {
  let item: TimelineItem

  var body: some View {
    switch item.kind {
    case .dayDivider(let date):
      Text(RoomViewModel.dayTitle(date))
        .textStyle(TextStyles.labelMedium)
        .foregroundStyle(SysColors.onSurface)
        .padding(.horizontal, RoomMetrics.capsuleInset)
        .padding(.vertical, 4)
        .background(SysColors.surface, in: Capsule())
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    case .stateNotice(let text):
      Text(text)
        .textStyle(TextStyles.bodySmall)
        .foregroundStyle(SysColors.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    case .message, .readMarker, .timelineStart:
      EmptyView()
    }
  }
}

/// Shown while a chat has no message on screen and its start is not reached.
private struct TimelinePlaceholderView: View {
  let placeholder: RoomViewModel.Placeholder
  let bubbleWidth: CGFloat
  let onLoadMore: () -> Void

  var body: some View {
    switch placeholder {
    case .loading:
      TimelineSkeleton(bubbleWidth: bubbleWidth)
    case .paused:
      VStack(spacing: 12) {
        Text(localized("No messages to show yet"))
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.onSurface)
        Text(localized("Earlier messages may still be on the server."))
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.textSecondary)
          .multilineTextAlignment(.center)
        Button(localized("Load earlier messages"), action: onLoadMore)
          .buttonStyle(.bordered)
      }
      .frame(maxWidth: .infinity, minHeight: 320)
      .padding(.horizontal, 24)
    }
  }
}

/// The card a chat with no message shows: a title, an optional line and what the chat offers.
private struct EmptyChatCardView: View {
  let card: EmptyChatCard

  var body: some View {
    VStack(spacing: 8) {
      Text(card.title)
        .textStyle(TextStyles.titleMedium)
        .foregroundStyle(SysColors.onSurface)
        .multilineTextAlignment(.center)
      if let description = card.description {
        Text(description)
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.textSecondary)
          .multilineTextAlignment(.center)
      }
      if !card.points.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(card.points, id: \.self) { point in
            Label(point, systemImage: "checkmark.circle.fill")
              .textStyle(TextStyles.bodyMedium)
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        .padding(.top, 4)
      }
    }
    .padding(16)
    .frame(maxWidth: 320)
    .background(SysColors.surface, in: RoundedRectangle(cornerRadius: 16))
    .frame(maxWidth: .infinity)
  }
}
