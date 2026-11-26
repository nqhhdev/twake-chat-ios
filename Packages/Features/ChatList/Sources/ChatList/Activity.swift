import DesignSystem
import Domain
import SwiftUI

extension ChatListViewModel {
  /// The rooms with something unread, the most recent first: the activity's inbox (web D57).
  public var inbox: [RoomSummary] {
    joinedRooms.filter { $0.isUnread && !$0.isSpace }
  }

  /// The rooms where someone mentioned the user and it is not read yet.
  public var mentioned: [RoomSummary] {
    joinedRooms.filter { $0.mentionCount > 0 }
  }

  /// Something waits in the activity's inbox: the bell shows its badge, also without a mention.
  public var hasActivity: Bool { !inbox.isEmpty }

  /// The mentions not read yet, read out with the bell.
  public var mentionTotal: Int {
    joinedRooms.reduce(0) { $0 + $1.mentionCount }
  }

  /// Loads the threads the user follows by choice (follow or mute), shared with the web app. Threads followed only by
  /// taking part are not listed: the SDK gives no list of them across rooms.
  public func loadFollowedThreads() async {
    guard let threadPrefs else { return }
    let roomIds = joinedRooms.filter { !$0.isSpace }.prefix(Self.reactionRoomLimit).map(\.id)
    async let followed = threadPrefs.followedThreads()
    async let active = threadPrefs.activeThreads(inRooms: Array(roomIds))
    followedThreads = FollowedThread.merged(followed: await followed, active: await active)
  }

  /// How many of the most recent chats the Activity reads reactions from: each one opens a timeline from the cache.
  static let reactionRoomLimit = 20

  /// Loads the reactions of other people on the user's messages in the most recent chats (web D58), from the history
  /// this device holds.
  public func loadReactions() async {
    guard let activityReactions else { return }
    let roomIds = joinedRooms.filter { !$0.isSpace }.prefix(Self.reactionRoomLimit).map(\.id)
    reactions = await activityReactions.reactions(inRooms: Array(roomIds))
  }

  /// What the Activity loads besides the room list: the followed threads and the reactions, side by side.
  public func loadActivity() async {
    async let threads: Void = loadFollowedThreads()
    async let reactions: Void = loadReactions()
    _ = await (threads, reactions)
  }

  /// "Sender reacted 👍 to your message", as the web's activity row says it.
  public static func title(of reaction: ActivityReaction) -> String {
    localized("\(reaction.senderName) reacted \(reaction.key) to your message")
  }

  /// "Sender: text" of a followed thread's root, or "Thread" when it could not be loaded.
  public static func preview(of thread: FollowedThread) -> String {
    if let latest = thread.latestText, !latest.isEmpty {
      let line = thread.latestSenderName.map { "\($0): \(latest)" } ?? latest
      return thread.replyCount > 1 ? localized("\(thread.replyCount) replies · \(line)") : line
    }
    guard let text = thread.rootText, !text.isEmpty else { return localized("Thread") }
    guard let sender = thread.rootSenderName, !sender.isEmpty else { return text }
    return "\(sender): \(text)"
  }
}

/// Activity (web D57, D58, D318): what needs the user, opened from the bell of the chat list. Mentions first, then the
/// reactions to the user's messages, then the threads the user follows, then the inbox of every room with something unread, each with a button that marks it
/// read; the saved messages last.
struct ActivityScreen: View {
  let viewModel: ChatListViewModel
  let onSelect: (RoomSummary) -> Void
  @Environment(\.openURL) private var openURL

  var body: some View {
    List {
      let mentioned = viewModel.mentioned
      if !mentioned.isEmpty {
        Section(localized("Mentions")) {
          ForEach(mentioned) { room in row(room, badge: "@\(room.mentionCount)") }
        }
      }
      let reactions = viewModel.reactions
      if !reactions.isEmpty {
        Section(localized("Reactions")) {
          ForEach(reactions) { reaction in reactionRow(reaction) }
        }
      }
      let followed = viewModel.followedThreads
      if !followed.isEmpty {
        Section(localized("Threads")) {
          ForEach(followed) { thread in threadRow(thread) }
        }
      }
      Section(localized("Inbox")) {
        let inbox = viewModel.inbox
        if inbox.isEmpty {
          Label(localized("You are all caught up."), systemImage: "checkmark.circle")
            .foregroundStyle(SysColors.textSecondary)
            .transition(.opacity)
        }
        ForEach(inbox) { room in
          row(room, badge: room.unreadCount > 0 ? "\(room.unreadCount)" : "•")
        }
      }
      if let saved = viewModel.saved {
        Section {
          NavigationLink {
            SavedMessagesScreen(repository: saved)
          } label: {
            Label(localized("Saved messages"), systemImage: "bookmark")
          }
        }
      }
    }
    .navigationTitle(localized("Activity"))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        MarkAllReadButton(viewModel: viewModel, rooms: viewModel.inbox)
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.inbox)
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.followedThreads)
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.reactions)
    .task { await viewModel.loadActivity() }
    .refreshable { await viewModel.loadActivity() }
  }

  /// A reaction to one of the user's messages: who and which emoji, the message, its chat. A tap opens the chat at the
  /// message, as a saved message opens.
  private func reactionRow(_ reaction: ActivityReaction) -> some View {
    Button {
      if let url = MatrixLink.room(idOrAlias: reaction.roomId, eventId: reaction.eventId, via: [])
        .url
      {
        openURL(url)
      }
    } label: {
      HStack(spacing: 12) {
        Text(reaction.key).font(.title2).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(ChatListViewModel.title(of: reaction)).font(.body.weight(.semibold)).lineLimit(1)
          if let text = reaction.messageText, !text.isEmpty {
            Text(text)
              .font(.subheadline)
              .foregroundStyle(SysColors.textSecondary)
              .lineLimit(2)
          }
          Text(reaction.roomName)
            .font(.caption)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(reaction.reactedAt, style: .relative)
          .font(.caption)
          .foregroundStyle(SysColors.textSecondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityHint(localized("Opens the message in its chat"))
  }

  /// A followed thread: its chat and its first message. A tap opens the chat at the thread's root, whose summary
  /// opens the thread, as a saved message opens.
  private func threadRow(_ thread: FollowedThread) -> some View {
    Button {
      if let url = MatrixLink.room(
        idOrAlias: thread.entry.roomId, eventId: thread.entry.threadId, via: []
      ).url {
        openURL(url)
      }
    } label: {
      HStack(spacing: 12) {
        Image(
          systemName: thread.entry.pref == .mute
            ? "bell.slash" : "bubble.left.and.text.bubble.right"
        )
        .foregroundStyle(SysColors.primary)
        VStack(alignment: .leading, spacing: 3) {
          Text(thread.roomName).font(.body.weight(.semibold)).lineLimit(1)
          Text(ChatListViewModel.preview(of: thread))
            .font(.subheadline)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityHint(localized("Opens the thread's chat"))
  }

  private func row(_ room: RoomSummary, badge: String) -> some View {
    HStack(spacing: 12) {
      Button {
        onSelect(room)
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(room.name).font(.body.weight(.semibold)).lineLimit(1)
          Text(ChatListViewModel.preview(of: room) ?? " ")
            .font(.subheadline)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Text(badge)
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(SysColors.primary, in: Capsule())
      Button {
        Task { await viewModel.setUnread(false, room: room) }
      } label: {
        Image(systemName: "envelope.open")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(localized("Mark \(room.name) as read"))
    }
    .transition(.move(edge: .trailing).combined(with: .opacity))
  }
}
