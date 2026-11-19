import DesignSystem
import Domain
import MapKit
import SwiftUI

/// A chat, laid out as the Flutter app's chat page: the timeline, newest at the bottom, with Twake bubbles (own
/// messages on the right), day dividers and room events as centred notices, then the composer. Bubbles are at most
/// `TwakeLayout.bubbleWidth(in:)` wide, so the chat reads the same on a phone, a folded and an unfolded Duo. It holds
/// no logic.
public struct RoomScreen: View {
  @Bindable var viewModel: RoomViewModel
  @State private var details: RoomDetailsViewModel?
  @State private var search: RoomSearchViewModel?
  @State private var isPickingDate = false
  @State private var pickedDate = Date()
  @State private var forwarding: ForwardItem?
  @State private var showsPinnedList = false
  @State private var showsThreads = false
  @State private var reporting: TimelineMessage?
  @State private var reportReason = ""
  @State private var blocking: TimelineMessage?
  @Environment(\.scenePhase) private var scenePhase

  public init(viewModel: RoomViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        if let warning = viewModel.sessionWarning {
          SessionWarningBanner(warning: warning) { viewModel.onFixSession?() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let warning = viewModel.identityWarnings.first {
          IdentityWarningBanner(warning: warning) { Task { await viewModel.accept(warning) } }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if viewModel.threadRootId == nil {
          PinnedBanner(viewModel: viewModel)
            .contextMenu {
              if !viewModel.pinned.isEmpty {
                Button("All pinned messages", systemImage: "pin") { showsPinnedList = true }
              }
            }
        }
        timeline(bubbleWidth: TwakeLayout.bubbleWidth(in: geometry.size.width))
        if let message = viewModel.errorMessage {
          Text(message)
            .textStyle(TextStyles.bodySmall)
            .foregroundStyle(SysColors.error)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        if viewModel.isSelectingMessages {
          MessageSelectionBar(viewModel: viewModel) { messages in
            forwarding = ForwardItem(messages: messages)
          }
          .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.isArchived {
          ArchivedRoomBar(viewModel: viewModel)
        } else if let link = viewModel.successorLink {
          SuccessorRoomBar(link: link)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !viewModel.canSendMessages {
          Label("Only admins and moderators can post here.", systemImage: "megaphone")
            .font(.subheadline)
            .foregroundStyle(SysColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.blockedUserId != nil {
          BlockedPersonBar(viewModel: viewModel)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
          ComposerView(viewModel: viewModel)
        }
      }
      .overlay {
        if let focus = viewModel.focus {
          MessageActionsOverlay(
            focus: focus, bubbleWidth: TwakeLayout.bubbleWidth(in: geometry.size.width),
            viewModel: viewModel,
            onForward: { message in forwarding = ForwardItem(message: message) },
            onReport: { message in
              reportReason = ""
              reporting = message
            },
            onBlock: { message in blocking = message }
          )
          .transition(.opacity)
        }
      }
    }
    .sheet(item: $forwarding) { item in ForwardSheet(messages: item.messages, viewModel: viewModel)
    }
    .sheet(
      isPresented: Binding(
        get: { viewModel.historyMessage != nil }, set: { if !$0 { viewModel.historyMessage = nil } }
      )
    ) {
      if let message = viewModel.historyMessage {
        EditHistorySheet(message: message, viewModel: viewModel)
      }
    }
    .overlay {
      if viewModel.isPreparingShare {
        ProgressView()
          .controlSize(.large)
          .padding(24)
          .background(.regularMaterial, in: .rect(cornerRadius: 16))
          .accessibilityLabel("Preparing to share")
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: viewModel.isPreparingShare)
    .sheet(item: $viewModel.sharedFiles) { files in ShareSheetLink(urls: files.urls) }
    .sheet(item: $viewModel.peopleSheet) { sheet in
      PeopleListSheet(sheet: sheet, viewModel: viewModel)
    }
    .sheet(isPresented: $showsThreads) {
      ThreadsListSheet(viewModel: viewModel) { root in
        showsThreads = false
        viewModel.openThread(root: root)
      }
    }
    .sheet(isPresented: $showsPinnedList) {
      PinnedListSheet(viewModel: viewModel) { eventId in
        showsPinnedList = false
        Task { await viewModel.jump(toEvent: eventId) }
      }
    }
    .alert(
      "Report this message?",
      isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })
    ) {
      TextField("Reason (optional)", text: $reportReason)
      Button("Cancel", role: .cancel) {}
      Button("Report", role: .destructive) {
        if let message = reporting {
          Task { await viewModel.report(message, reason: reportReason) }
        }
      }
    } message: {
      Text("The server's moderators will see it.")
    }
    .confirmationDialog(
      blocking.map { "Block \($0.senderName)?" } ?? "",
      isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
      titleVisibility: .visible
    ) {
      Button("Block", role: .destructive) {
        if let message = blocking { Task { await viewModel.block(message) } }
      }
    } message: {
      Text("You will no longer see their messages or invitations, in any chat.")
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.focus != nil) { _, shown in shown
    }
    .background(SysColors.background)
    .overlay(alignment: .top) {
      if let toast = viewModel.toast { Toast(text: toast) }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.toast)
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.pinned)
    .task { await viewModel.refreshSessionWarning() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await viewModel.refreshSessionWarning() }
        Task { await viewModel.retryDecryption() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .encryptionKeysImported)) { _ in
      Task { await viewModel.retryDecryption() }
    }
    .sensoryFeedback(.success, trigger: viewModel.toast) { _, new in new != nil }
    .navigationTitle(viewModel.threadRootId == nil ? viewModel.roomName : "Thread")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewModel.threadRootId != nil {
        ToolbarItem(placement: .principal) {
          VStack(spacing: 0) {
            Text("Thread").textStyle(TextStyles.titleMedium)
            Text(viewModel.roomName)
              .textStyle(TextStyles.labelSmall)
              .foregroundStyle(SysColors.textSecondary)
              .lineLimit(1)
          }
          .accessibilityElement(children: .combine)
        }
        if viewModel.canFollowThread {
          ToolbarItem(placement: .topBarTrailing) { ThreadFollowMenu(viewModel: viewModel) }
        }
      } else {
        // As in the Flutter chat, the header opens the chat details.
        ToolbarItem(placement: .principal) {
          Button {
            details = viewModel.makeDetails()
          } label: {
            HStack(spacing: 8) {
              TwakeAvatar(
                name: viewModel.roomName, size: 32, pictureID: viewModel.roomAvatar?.source,
                load: viewModel.roomAvatar.map { reference in
                  { @Sendable [viewModel] in await viewModel.picture(reference) }
                })
              VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                  Text(viewModel.roomName).textStyle(TextStyles.titleMedium).lineLimit(1)
                  if viewModel.isEncrypted {
                    Image(systemName: "lock.fill")
                      .font(.caption2)
                      .foregroundStyle(SysColors.textSecondary)
                      .accessibilityLabel("Encrypted")
                  }
                }
                if let presence = viewModel.headerSubtitle {
                  Text(presence)
                    .textStyle(TextStyles.labelSmall)
                    .foregroundStyle(
                      presence == "Online"
                        ? AnyShapeStyle(.green) : AnyShapeStyle(SysColors.textSecondary)
                    )
                    .lineLimit(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityHint("Shows the chat details")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu("More", systemImage: "ellipsis.circle") {
            if viewModel.canSearch {
              Button("Search", systemImage: "magnifyingglass") { search = viewModel.makeSearch() }
            }
            if viewModel.canOpenThreads {
              Button("Threads", systemImage: "bubble.left.and.text.bubble.right") {
                showsThreads = true
              }
            }
            Button("Go to Date", systemImage: "calendar") { isPickingDate = true }
            Button("Jump to Start", systemImage: "arrow.up.to.line") {
              Task { await viewModel.jumpToStart() }
            }
            Button("Select Messages", systemImage: "checkmark.circle") {
              if let last = viewModel.rows.reversed().lazy.compactMap(\.selectableMessage).first {
                viewModel.startSelecting(last)
              }
            }
          }
        }
      }
    }
    .navigationDestination(item: $viewModel.openedThread) { thread in RoomScreen(viewModel: thread)
    }
    .navigationDestination(item: $details) { details in RoomDetailsScreen(viewModel: details) }
    .navigationDestination(item: $search) { search in
      RoomSearchScreen(viewModel: search) { eventId in
        self.search = nil
        // A search result may be far back: look further than for a reply.
        Task { await viewModel.jump(toEvent: eventId, maxPages: 50) }
      }
    }
    .task(id: viewModel.roomId) { await viewModel.start() }
    // Cancels the 15 s poll when the scene leaves the foreground (issue #111).
    .task(id: "\(viewModel.roomId)-\(scenePhase == .active)") {
      guard scenePhase == .active else { return }
      await viewModel.watchPresence()
    }
    .sheet(isPresented: $isPickingDate) {
      NavigationStack {
        DatePicker("Date", selection: $pickedDate, in: ...Date(), displayedComponents: .date)
          .datePickerStyle(.graphical)
          .padding()
          .navigationTitle("Go to Date")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") { isPickingDate = false }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Go") {
                isPickingDate = false
                let date = pickedDate
                Task { await viewModel.jump(toDate: date) }
              }
            }
          }
      }
      .presentationDetents([.medium, .large])
    }
  }

  @ViewBuilder private func timeline(bubbleWidth: CGFloat) -> some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label(message, systemImage: "exclamationmark.triangle")
      } description: {
        Text("The chat may still be syncing. Try again in a moment.")
      } actions: {
        Button("Retry") { Task { await viewModel.start() } }
      }
    case .loaded:
      TimelineScroll(viewModel: viewModel, bubbleWidth: bubbleWidth)
    }
  }
}

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

  @State private var position = ScrollPosition(idType: String.self, edge: .bottom)
  @State private var isAtBottom = true
  /// The newest row when the user scrolled up; what arrives after it is counted on the scroll-down button.
  @State private var lastSeenRowId: String?
  /// The row at the top of the viewport when a page was asked for, so a prepend keeps it there.
  @State private var paginationAnchorId: String?

  var body: some View {
    let rows = viewModel.rows
    let newCount = ChatRow.incomingCount(after: lastSeenRowId, in: rows)
    ScrollView {
      LazyVStack(spacing: 0) {
        if let placeholder = viewModel.placeholder {
          // No message to show yet: say so in the middle of the screen instead of a small spinner at its top.
          TimelinePlaceholderView(placeholder: placeholder) {
            Task { await viewModel.resumeHistory() }
          }
          .task(id: placeholder) {
            if placeholder == .loading { await viewModel.loadOlderWhileVisible() }
          }
        } else if !viewModel.reachedStart {
          if viewModel.isHistoryPaused {
            // Loading stopped by itself (many pages with nothing to show, or pages failing): the user asks for more.
            Button("Load earlier messages") { Task { await viewModel.resumeHistory() } }
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
            .transition(Self.insertion(for: row))
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      // Only the newest row animates in; loading older messages at the top does not move the view.
      .animation(.spring(response: 0.38, dampingFraction: 0.78), value: rows.last?.id)
      .scrollTargetLayout()
    }
    .scrollPosition($position, anchor: .top)
    .onChange(of: viewModel.scrollTarget) { _, target in
      guard let target else { return }
      withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
        position.scrollTo(id: target, anchor: .center)
      }
      viewModel.scrollTarget = nil
    }
    // Open on the newest message, and stay on it as messages arrive or pictures load.
    .defaultScrollAnchor(.bottom)
    // Pinning size changes to the bottom while scrolled up would drag the reader with new
    // messages or with a prepend; only the bottom of a chat they are already following stays put.
    .defaultScrollAnchor(isAtBottom ? .bottom : nil, for: .sizeChanges)
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
                Text(newCount > 99 ? "99+" : "\(newCount)")
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
            ? "Scroll to the latest message, \(newCount) new" : "Scroll to the latest message"
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
    withTransaction(transaction) { position.scrollTo(id: id, anchor: .top) }
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
          Text(isOpen ? "Hide changes" : "\(model.texts.count) changes")
          Image(systemName: "chevron.down")
            .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(SysColors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SysColors.surface, in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityHint(isOpen ? "Hides the room changes" : "Shows the room changes")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(SysColors.surface, in: Capsule())
        .padding(.vertical, 10)
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

/// A message bubble in its sender's group, as Telegram and iMessage show it: the sender's name on the first bubble,
/// the avatar and the tail on the last, 2 pt between bubbles of a group and 8 pt between groups. Swipe it towards the
/// leading edge to reply, double-tap it to send ❤️, long-press it to lift it with the tapbacks and actions, as iMessage.
struct MessageRow: View {
  let message: TimelineMessage
  let position: GroupPosition
  /// Someone else has read up to this message; own messages show a double tick.
  let isRead: Bool
  let bubbleWidth: CGFloat
  let viewModel: RoomViewModel
  var album: AlbumRowModel?
  /// Drawn in the long-press layer: no gestures, no menu.
  var isPreview = false

  /// How far the bubble is dragged for swipe-to-reply.
  @State private var swipe: CGFloat = 0
  @State private var didReachReply = false
  @State private var heartBurst = 0
  @State private var frameBox = FrameBox()

  /// The swipe that triggers a reply, as Telegram's.
  private static let replyThreshold: CGFloat = 56

  var body: some View {
    VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
      HStack(alignment: .bottom, spacing: 8) {
        if !message.isOwn {
          // The avatar sits by the last bubble of a group; the others keep its space so the bubbles line up.
          if position.isLast {
            TwakeAvatar(
              name: message.senderName, size: 32, pictureID: message.senderAvatar?.source,
              load: message.senderAvatar.map { reference in
                { @Sendable [viewModel] in await viewModel.picture(reference) }
              })
          } else {
            Color.clear.frame(width: 32, height: 1)
          }
        }
        Group {
          if message.isEmojiOnly, message.reply == nil { bigEmoji } else { bubble }
        }
        .overlay { HeartBurst(trigger: heartBurst) }
        .simultaneousGesture(
          LongPressGesture(minimumDuration: 0.35).onEnded { _ in showActions() },
          isEnabled: !isPreview
        )
        .accessibilityAction(named: "Message actions") { showActions() }
      }
      .offset(x: swipe)
      .background(alignment: .trailing) { replyHint }
      .simultaneousGesture(swipeToReply, isEnabled: !isPreview)
      if !message.reactions.isEmpty { reactions }
      if let thread = message.thread, thread.replyCount > 0, viewModel.canOpenThreads, !isPreview {
        ThreadSummaryButton(thread: thread, isOwn: message.isOwn) {
          viewModel.openThread(on: message)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
    .padding(.top, position.isFirst ? 8 : 2)
    .background {
      if !isPreview, message.eventId != nil, viewModel.highlightedEventId == message.eventId {
        RoundedRectangle(cornerRadius: 14).fill(SysColors.primary.opacity(0.14))
          .padding(.horizontal, -6)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: viewModel.highlightedEventId)
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .global)
    } action: {
      frameBox.frame = $0
    }
    .opacity(!isPreview && viewModel.focus?.message == message ? 0 : 1)
    .sensoryFeedback(.impact(weight: .light), trigger: didReachReply) { _, reached in reached }
  }

  /// Lifts this message into the actions layer (long press, or the accessibility action).
  private func showActions() {
    guard !isPreview, viewModel.focus == nil else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
      viewModel.focus = MessageFocus(
        message: message, position: position, isRead: isRead, album: album,
        frame: frameBox.frame)
    }
  }

  /// The reply arrow that fades and grows in behind the bubble while it is swiped.
  private var replyHint: some View {
    let progress = min(1, -swipe / Self.replyThreshold)
    return Image(systemName: "arrowshape.turn.up.left.circle.fill")
      .font(.system(size: 26))
      .foregroundStyle(SysColors.primary)
      .scaleEffect(0.5 + 0.5 * progress)
      .opacity(progress)
      .padding(.trailing, 4)
  }

  private var swipeToReply: some Gesture {
    DragGesture(minimumDistance: 16)
      .onChanged { value in
        // Only a mostly horizontal swipe towards the leading edge; vertical drags scroll the timeline.
        guard message.eventId != nil,
          abs(value.translation.width) > abs(value.translation.height) * 1.5
        else {
          return
        }
        let dragged = min(0, value.translation.width)
        // Resist past the threshold, as a rubber band.
        swipe =
          dragged < -Self.replyThreshold
          ? -Self.replyThreshold + (dragged + Self.replyThreshold) / 3 : dragged
        let reached = -swipe >= Self.replyThreshold
        if reached != didReachReply { didReachReply = reached }
      }
      .onEnded { _ in
        if didReachReply { viewModel.reply(to: message) }
        didReachReply = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { swipe = 0 }
      }
  }

  /// Emojis alone, large and without a bubble, with the time under them, as iMessage and Telegram show them.
  private var bigEmoji: some View {
    VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
      if case .text(let text) = message.body {
        Text(text).font(.system(size: 48))
      }
      Text(message.date, format: .dateTime.hour().minute())
        .textStyle(TextStyles.labelSmall)
        .foregroundStyle(SysColors.textSecondary)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      guard !isPreview, message.eventId != nil else { return }
      heartBurst += 1
      Task { await viewModel.toggleReaction("❤️", on: message) }
    }
  }

  /// The widest the text inside the bubble may be: the bubble's limit less its padding and, for others, the avatar.
  private var contentWidth: CGFloat {
    bubbleWidth - 24 - (message.isOwn ? 0 : 40)
  }

  /// The bubble hugs its content: `HuggingStack` makes it as wide as its widest part, at most `contentWidth`, so a
  /// short message gets a short bubble and a long one wraps at the cap.
  private var bubble: some View {
    HuggingStack(maxWidth: contentWidth, spacing: 4) {
      if !message.isOwn, position.isFirst {
        Text(message.senderName)
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.primary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      // An album replies with its first picture, as Twake web sends and shows it.
      let replying = album?.messages.first ?? message
      if let reply = replying.reply {
        HStack(spacing: 6) {
          RoundedRectangle(cornerRadius: 1.5).fill(SysColors.primary).frame(width: 3)
          VStack(alignment: .leading, spacing: 0) {
            Text(reply.senderName).textStyle(TextStyles.labelMedium).foregroundStyle(
              SysColors.primary)
            Text(reply.text ?? "…").textStyle(TextStyles.bodySmall).foregroundStyle(
              SysColors.textSecondary
            )
            .lineLimit(2)
          }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(SysColors.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
          guard !isPreview, let target = replying.replyToEventId else { return }
          Task { await viewModel.jump(toEvent: target) }
        }
        .accessibilityAddTraits(replying.replyToEventId == nil ? [] : .isButton)
        .accessibilityHint(replying.replyToEventId == nil ? "" : "Shows the original message")
      }
      if let album {
        AlbumGrid(album: album, width: contentWidth, viewModel: viewModel)
        if let caption = album.caption { captionText(caption) }
      } else if let media = message.media {
        MessageMediaView(message: message, media: media, width: contentWidth, viewModel: viewModel)
        if let caption = Self.caption(of: message.body) { captionText(caption) }
      } else if let poll = message.poll {
        PollView(poll: poll, message: message, viewModel: viewModel)
          .frame(width: contentWidth)
      } else {
        MessageBody(
          content: message.body, formatted: message.formatted,
          isDeviceVerified: viewModel.sessionWarning == nil
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        if case .text(let text) = message.body, let link = RoomViewModel.previewLink(in: text) {
          LinkPreviewCard(url: link, width: contentWidth, viewModel: viewModel)
        }
      }
      HStack(spacing: 4) {
        if message.isEdited { Text("edited") }
        Text(message.date, format: .dateTime.hour().minute())
        if message.isOwn, message.sendState == .failed, !isPreview {
          Button {
            Task { await viewModel.retry(message) }
          } label: {
            Label("Not sent, tap to retry", systemImage: "arrow.clockwise")
              .foregroundStyle(SysColors.error)
          }
          .buttonStyle(.plain)
        } else if message.isOwn {
          sendStateIcon.animation(
            .spring(response: 0.3, dampingFraction: 0.7), value: isRead)
        }
      }
      .textStyle(TextStyles.labelSmall)
      .foregroundStyle(SysColors.textSecondary)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      message.isOwn ? SysColors.primaryContainer : SysColors.onPrimary,
      in: TwakeBubbleShape(isOwn: message.isOwn, isFirst: position.isFirst, isLast: position.isLast)
    )
    .shadow(color: .black.opacity(message.isOwn ? 0 : 0.10), radius: 1, y: 0.5)
    .onTapGesture(count: 2) {
      // Double-tap sends ❤️, as a tapback; pictures keep the single tap that opens them.
      guard !isPreview, message.media == nil, message.eventId != nil else { return }
      heartBurst += 1
      Task { await viewModel.toggleReaction("❤️", on: message) }
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: heartBurst)
  }

  private func captionText(_ caption: String) -> some View {
    Text(caption)
      .textStyle(TextStyleToken(size: 15, lineHeight: 20, weight: .regular, letterSpacing: 0))
      .foregroundStyle(SysColors.onSurface)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The caption under a picture or video; a file's or a voice message's row already shows its name.
  static func caption(of body: TimelineMessage.Body) -> String? {
    switch body {
    case .image(let caption?), .video(let caption?):
      caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption
    default: nil
    }
  }

  /// Sending, sent and failed swap with the symbol replace effect; once someone has read the message, a second
  /// check slides in and both turn `primary`, as the Flutter chat's double tick.
  @ViewBuilder private var sendStateIcon: some View {
    if message.sendState == .sent, isRead {
      HStack(spacing: -7) {
        Image(systemName: "checkmark")
        Image(systemName: "checkmark").transition(.move(edge: .leading).combined(with: .opacity))
      }
      .foregroundStyle(SysColors.primary)
      .accessibilityLabel("Read")
    } else {
      let symbol =
        switch message.sendState {
        case .sent: "checkmark"
        case .sending: "clock"
        case .failed: "exclamationmark.circle"
        }
      Image(systemName: symbol)
        .foregroundStyle(message.sendState == .failed ? SysColors.error : SysColors.textSecondary)
        .contentTransition(.symbolEffect(.replace))
        .animation(.default, value: message.sendState)
    }
  }

  /// Reaction chips: a new one pops in, a count rolls to its new value, and the user's own are highlighted.
  private var reactions: some View {
    HStack(spacing: 4) {
      ForEach(message.reactions) { reaction in
        Button {
          Task { await viewModel.toggleReaction(reaction.key, on: message) }
        } label: {
          HStack(spacing: 3) {
            Text(reaction.key)
            Text("\(reaction.count)")
              .contentTransition(.numericText(value: Double(reaction.count)))
          }
          .textStyle(TextStyles.labelMedium)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(
            reaction.includesOwn ? SysColors.primaryContainer : SysColors.surface, in: Capsule()
          )
          .overlay(
            Capsule().strokeBorder(
              SysColors.primary.opacity(reaction.includesOwn ? 0.5 : 0), lineWidth: 1)
          )
        }
        .buttonStyle(PressScaleButtonStyle())
        .contextMenu {
          Button("See who reacted", systemImage: "person.2") { viewModel.showReactors(reaction) }
        }
        .transition(.scale(scale: 0.3).combined(with: .opacity))
        .sensoryFeedback(.selection, trigger: reaction.includesOwn)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: message.reactions)
    .padding(.leading, message.isOwn ? 0 : 40)
    .allowsHitTesting(!isPreview)
  }

}

/// The heart that bursts out of a bubble when it is double-tapped: it grows, rises and fades.
struct HeartBurst: View {
  let trigger: Int

  var body: some View {
    Image(systemName: "heart.fill")
      .font(.system(size: 44))
      .foregroundStyle(.pink)
      .keyframeAnimator(initialValue: Burst(), trigger: trigger) { content, burst in
        content.scaleEffect(burst.scale).offset(y: burst.rise).opacity(burst.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.scale) {
          SpringKeyframe(1.3, duration: 0.25, spring: .bouncy)
          LinearKeyframe(1.0, duration: 0.15)
          LinearKeyframe(0.8, duration: 0.3)
        }
        KeyframeTrack(\.rise) {
          LinearKeyframe(0, duration: 0.35)
          CubicKeyframe(-30, duration: 0.35)
        }
        KeyframeTrack(\.opacity) {
          LinearKeyframe(1, duration: 0.05)
          LinearKeyframe(1, duration: 0.4)
          LinearKeyframe(0, duration: 0.25)
        }
      }
      .allowsHitTesting(false)
  }

  struct Burst {
    var scale: CGFloat = 0.2
    var rise: CGFloat = 0
    var opacity: Double = 0
  }
}

/// A button that shrinks a little while pressed and springs back.
struct PressScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.88 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
  }
}

/// The content of a message, by kind. A text, emote or notice shows as its sender formatted it when it has an HTML
/// body (bold, links, mentions, quotes, lists, code), as the web client draws it.
struct MessageBody: View {
  let content: TimelineMessage.Body
  var formatted: AttributedString?
  /// This device is verified, which decides the help under a message that cannot be decrypted.
  var isDeviceVerified = true
  /// The reader tapped the message: its spoilers show.
  @State private var revealsSpoilers = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The text with each spoiler covered by a solid block and its links turned off, until revealed.
  static func concealingSpoilers(_ text: AttributedString) -> AttributedString {
    var result = text
    for run in text.runs where run[SpoilerAttribute.self] == true {
      result[run.range].foregroundColor = .clear
      result[run.range].backgroundColor = Color.secondary.opacity(0.45)
      result[run.range].link = nil
    }
    return result
  }

  /// A formatted text, its spoilers covered until the reader taps it.
  @ViewBuilder private func rich(_ text: AttributedString) -> some View {
    if text.hasSpoiler {
      Text(revealsSpoilers ? text : Self.concealingSpoilers(text))
        .contentTransition(.opacity)
        .onTapGesture {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { revealsSpoilers.toggle() }
        }
        .accessibilityHint(revealsSpoilers ? "Hides the spoiler" : "Shows the spoiler")
        .accessibilityAddTraits(.isButton)
    } else {
      Text(text)
    }
  }

  /// A message without HTML: its inline Markdown (bold, italic, code, links) and bare addresses as links. The text is
  /// never looked up as a localisation key.
  static func plain(_ text: String) -> AttributedString {
    let parsed =
      (try? AttributedString(
        markdown: text,
        options: .init(
          allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
          failurePolicy: .returnPartiallyParsedIfPossible)))
      ?? AttributedString(text)
    return MatrixHTML.linkingBareAddresses(parsed)
  }

  /// An emote, as "* text" in italics.
  static func emote(_ text: AttributedString) -> AttributedString {
    var line = AttributedString("* ") + text
    for run in line.runs {
      line[run.range].inlinePresentationIntent =
        (run.inlinePresentationIntent ?? []).union(.emphasized)
    }
    return line
  }

  var body: some View {
    Group {
      switch content {
      case .text(let text): rich(formatted ?? Self.plain(text))
      case .emote(let text): rich(Self.emote(formatted ?? Self.plain(text)))
      case .notice(let text):
        rich(formatted ?? Self.plain(text)).foregroundStyle(SysColors.textSecondary)
      case .image(let caption): Label(caption ?? "Picture", systemImage: "photo")
      case .video(let caption): Label(caption ?? "Video", systemImage: "video")
      case .audio(let caption): Label(caption ?? "Audio", systemImage: "waveform")
      case .file(let name): Label(name, systemImage: "doc")
      case .location(let text, let place):
        if let place {
          LocationCard(text: text, place: place)
        } else {
          Label(text, systemImage: "mappin.and.ellipse")
        }
      case .sticker(let text): Text(text)
      case .poll(let question): Label(question, systemImage: "chart.bar")
      case .redacted:
        Label("This message has been deleted", systemImage: "trash").foregroundStyle(
          SysColors.textSecondary)
      case .unableToDecrypt(let reason):
        // The web's wording: the line, then why the key is missing or what brings it back.
        VStack(alignment: .leading, spacing: 2) {
          Label("This message cannot be read on this device yet.", systemImage: "lock.badge.clock")
          Text(reason.help(isDeviceVerified: isDeviceVerified))
            .textStyle(TextStyles.labelSmall)
        }
        .foregroundStyle(SysColors.textSecondary)
      case .unsupported:
        Text("Unknown event").foregroundStyle(SysColors.textSecondary)
      }
    }
    .textStyle(TextStyleToken(size: 15, lineHeight: 20, weight: .regular, letterSpacing: 0))
    .foregroundStyle(SysColors.onSurface)
  }
}

/// A vertical stack as wide as its widest child at its natural size, but at most `maxWidth`; every child is then laid
/// out at that width, so text wraps at it and trailing parts (the time) line up on the right.
struct HuggingStack: Layout {
  let maxWidth: CGFloat
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = width(of: subviews)
    let heights = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }
    return CGSize(
      width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for subview in subviews {
      let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
      subview.place(
        at: CGPoint(x: bounds.minX, y: y),
        proposal: ProposedViewSize(width: bounds.width, height: height))
      y += height + spacing
    }
  }

  private func width(of subviews: Subviews) -> CGFloat {
    min(maxWidth, subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0)
  }
}

/// In place of the composer in a chat the user left: why it is read-only, and Rejoin.
/// In place of the composer once the room was upgraded (`m.room.tombstone`, Flutter `ChatUpgradeBanner`): the
/// conversation goes on in the new room, which the button opens.
struct SuccessorRoomBar: View {
  let link: URL
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(spacing: 8) {
      Label(
        "This chat has been replaced and is no longer active.",
        systemImage: "arrow.up.forward.square"
      )
      .font(.subheadline)
      .foregroundStyle(SysColors.textSecondary)
      .multilineTextAlignment(.center)
      Button("Go to the new chat") { openURL(link) }
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(12)
    .background(.bar)
  }
}

/// In place of the composer in a direct chat with someone the user blocked (Flutter `BlockedUserBanner`).
struct BlockedPersonBar: View {
  let viewModel: RoomViewModel
  @State private var isWorking = false

  var body: some View {
    VStack(spacing: 8) {
      Label("You blocked this person.", systemImage: "hand.raised")
        .font(.subheadline)
        .foregroundStyle(SysColors.textSecondary)
      Button {
        isWorking = true
        Task {
          await viewModel.unblock()
          isWorking = false
        }
      } label: {
        Group { if isWorking { ProgressView() } else { Text("Unblock") } }
          .frame(maxWidth: 280)
      }
      .buttonStyle(.bordered)
      .disabled(isWorking)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.bar)
  }
}

/// Above the timeline when a member's identity changed (Element X `IdentityPinningViolation`): their messages may
/// not be from them until the user accepts the new identity, or checks with them first.
struct IdentityWarningBanner: View {
  let warning: IdentityWarning
  let onAccept: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.shield.fill")
        .font(.title3)
        .foregroundStyle(
          warning.kind == .verifiedChanged
            ? AnyShapeStyle(SysColors.error) : AnyShapeStyle(Color.orange)
        )
        .symbolEffect(.pulse, options: .repeat(2), isActive: !reduceMotion)
      VStack(alignment: .leading, spacing: 6) {
        Text(
          warning.kind == .verifiedChanged
            ? "\(warning.name)'s verified identity was reset."
            : "\(warning.name)'s identity was reset."
        )
        .font(.subheadline.weight(.semibold))
        Text("Check with them another way before trusting new messages.")
          .font(.footnote)
          .foregroundStyle(SysColors.textSecondary)
        Button(warning.kind == .verifiedChanged ? "Withdraw verification" : "OK, I understand") {
          onAccept()
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(.bar)
    .accessibilityElement(children: .contain)
  }
}

struct ArchivedRoomBar: View {
  let viewModel: RoomViewModel

  var body: some View {
    VStack(spacing: 8) {
      Text("You left this chat.")
        .font(.subheadline)
        .foregroundStyle(SysColors.textSecondary)
      Button {
        Task { await viewModel.rejoin() }
      } label: {
        Group {
          if viewModel.isRejoining { ProgressView() } else { Text("Rejoin") }
        }
        .frame(maxWidth: 280)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isRejoining)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.bar)
  }
}

/// Above the timeline when encrypted messages may not show on this device (Flutter `ChatDeviceVerificationBanner`): why,
/// and the button that opens Privacy & Security to verify the device or enter the recovery key. It stays until that is
/// done, as on the Flutter app's phone layout.
struct SessionWarningBanner: View {
  let warning: SessionWarning
  let onFix: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.shield.fill")
        .font(.title3)
        .foregroundStyle(SysColors.warning)
        .accessibilityHidden(true)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(SysColors.onSurface)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 4)
      Button(action: onFix) {
        Text(warning == .unverified ? "Verify" : "Enter Key").font(.subheadline.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.bar)
    .overlay(alignment: .bottom) { Rectangle().fill(SysColors.surface).frame(height: 1) }
  }

  private var message: String {
    switch warning {
    case .unverified: "Encrypted messages may not show until this device is verified."
    case .recoveryIncomplete: "Encrypted messages may not show until you enter your recovery key."
    }
  }
}

/// The card under a message's first web link (Flutter `TwakeLinkPreview`): the page's picture, site, title and
/// description, as the homeserver previews it. It shows nothing until the preview arrives, or when there is none; a tap
/// opens the link.
struct LinkPreviewCard: View {
  let url: URL
  let width: CGFloat
  let viewModel: RoomViewModel
  @State private var preview: LinkPreview?
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      if let preview {
        Button {
          guard viewModel.focus == nil else { return }
          openURL(preview.url)
        } label: {
          card(preview)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      }
    }
    .task(id: url) {
      let loaded = await viewModel.linkPreview(of: url)
      withAnimation(.easeOut(duration: 0.2)) { preview = loaded }
    }
  }

  private func card(_ preview: LinkPreview) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let image = preview.image {
        let height = min(160, width * (image.aspectRatio ?? 0.52))
        RemoteImage(
          media: image, size: CGSize(width: width, height: height), repository: viewModel.media
        )
        .frame(width: width, height: height)
        .clipped()
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(preview.siteName ?? preview.url.host() ?? "")
          .font(.caption.weight(.medium))
          .foregroundStyle(SysColors.primary)
          .lineLimit(1)
        if let title = preview.title {
          Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        if let description = preview.description {
          Text(description).font(.footnote).foregroundStyle(SysColors.textSecondary).lineLimit(3)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
    }
    .frame(width: width, alignment: .leading)
    .background(SysColors.surface.opacity(0.7))
    .clipShape(.rect(cornerRadius: 10))
    .overlay(alignment: .leading) {
      Rectangle().fill(SysColors.primary).frame(width: 3)
        .clipShape(.rect(topLeadingRadius: 10, bottomLeadingRadius: 10))
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens the link")
  }
}

/// The card a chat with no message shows: a title, an optional line and what the chat offers.
/// Shown while a chat has no message on screen and its start is not reached.
private struct TimelinePlaceholderView: View {
  let placeholder: RoomViewModel.Placeholder
  let onLoadMore: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      switch placeholder {
      case .loading:
        ProgressView()
        Text("Loading messages…")
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.textSecondary)
      case .paused:
        Text("No messages to show yet")
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.onSurface)
        Text("Earlier messages may still be on the server.")
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.textSecondary)
          .multilineTextAlignment(.center)
        Button("Load earlier messages", action: onLoadMore)
          .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
    .padding(.horizontal, 24)
  }
}

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

/// A location message: a still map with a pin, and the sender's text. A tap opens the place in Apple Maps.
private struct LocationCard: View {
  let text: String
  let place: GeoPoint
  @Environment(\.openURL) private var openURL

  private var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
  }

  var body: some View {
    Button {
      if let url = place.appleMapsURL { openURL(url) }
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Map(
          initialPosition: .region(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)),
          interactionModes: []
        ) {
          Marker("", coordinate: coordinate)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        Label(text, systemImage: "mappin.and.ellipse")
          .multilineTextAlignment(.leading)
        Text("Open in Maps")
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.textSecondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Location: \(text). Open in Maps")
  }
}
