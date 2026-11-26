import DesignSystem
import Domain
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
  /// The room's Meet calls (#92); `nil` when the app gave no call repository.
  @State private var calls: MeetCallViewModel?
  @State private var roomCall: RoomCallViewModel?
  @Environment(\.scenePhase) private var scenePhase
  private let meetCalls: (any MeetCallRepository)?

  public init(
    viewModel: RoomViewModel, meetCalls: (any MeetCallRepository)? = nil,
    roomCalls: (any RoomCallRepository)? = nil
  ) {
    self.viewModel = viewModel
    self.meetCalls = meetCalls
    _calls = State(
      initialValue: meetCalls.map { MeetCallViewModel(roomId: viewModel.roomId, repository: $0) })
    _roomCall = State(
      initialValue: roomCalls.map {
        RoomCallViewModel(
          roomId: viewModel.roomId, repository: $0, system: CallKitReporter.shared)
      })
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
        if let roomCall, roomCall.isAvailable, roomCall.state.isActive, roomCall.activeCall == nil {
          ActiveCallBanner(calls: roomCall, title: viewModel.roomName)
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
        if geometry.size.width > 0 {
          timeline(bubbleWidth: TwakeLayout.bubbleWidth(in: geometry.size.width))
        } else {
          Color.clear
        }
        if let message = viewModel.errorMessage {
          Text(message)
            .textStyle(TextStyles.bodySmall)
            .foregroundStyle(SysColors.error)
            .padding(.horizontal, RoomMetrics.barInset)
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
      .attachmentDrop(viewModel)
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
    .sheet(
      isPresented: Binding(
        get: { viewModel.infoMessage != nil }, set: { if !$0 { viewModel.infoMessage = nil } })
    ) {
      if let message = viewModel.infoMessage { MessageInfoSheet(message: message) }
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
      if phase == ScenePhase.active {
        Task { await viewModel.refreshSessionWarning() }
        Task { await viewModel.retryDecryption() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .encryptionKeysImported)) { _ in
      Task { await viewModel.retryDecryption() }
    }
    .sensoryFeedback(.success, trigger: viewModel.toast) { _, new in new != nil }
    .environment(calls)
    .task(id: viewModel.roomId) { await calls?.load() }
    .roomCalls(roomCall, roomId: viewModel.roomId)
    .alert(
      calls?.errorMessage ?? "",
      isPresented: Binding(
        get: { calls?.errorMessage != nil }, set: { if !$0 { calls?.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    }
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
        // As in the Flutter chat: a call needs a Meet server and the right to post, since it is a message.
        if let roomCall, roomCall.isAvailable, !viewModel.isArchived {
          ToolbarItem(placement: .topBarTrailing) {
            RoomCallButton(calls: roomCall, title: viewModel.roomName)
          }
        } else if let calls, calls.baseURL != nil, viewModel.canSendMessages, !viewModel.isArchived
        {
          ToolbarItem(placement: .topBarTrailing) { MeetCallButton(calls: calls) }
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
    .navigationDestination(item: $viewModel.openedThread) { thread in
      RoomScreen(viewModel: thread, meetCalls: meetCalls)
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
    .task(id: presenceTaskID) {
      guard isSceneActive else { return }
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

  private var isSceneActive: Bool { scenePhase == ScenePhase.active }

  private var presenceTaskID: String { "\(viewModel.roomId)-\(isSceneActive)" }

  @ViewBuilder private func timeline(bubbleWidth: CGFloat) -> some View {
    switch viewModel.state {
    case .loading:
      TimelineSkeleton(bubbleWidth: bubbleWidth)
        .padding(.horizontal, RoomMetrics.gutter)
        .padding(.vertical, 8)
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
