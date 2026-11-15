import DesignSystem
import Domain
import SwiftUI

/// Gives the timeline of one thread of the room, by its root event id (`m.thread`).
public typealias ThreadTimeline = @MainActor (_ rootEventId: String) -> any TimelineRepository

extension RoomViewModel {
  /// Threads open from this room: it was given thread timelines and is not itself a thread.
  public var canOpenThreads: Bool { hasThreadTimelines && threadRootId == nil }

  /// The room's threads, for its Threads list.
  public func loadThreads() async -> [ThreadListEntry] { await repository.threads() }

  /// Opens a thread of the Threads list.
  public func openThread(root eventId: String) {
    guard canOpenThreads else { return }
    openedThread = makeThread(root: eventId)
  }

  /// Opens the thread started on this message, or starts one: the room pushes it as its own screen.
  public func openThread(on message: TimelineMessage) {
    guard canOpenThreads, let eventId = message.threadRootId ?? message.eventId else { return }
    focus = nil
    openedThread = makeThread(root: eventId)
  }
}

/// One room screen is one value: the room pushes a thread with `navigationDestination(item:)`.
extension RoomViewModel: Hashable {
  nonisolated public static func == (lhs: RoomViewModel, rhs: RoomViewModel) -> Bool { lhs === rhs }
  nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Under a message that started a thread: the reply count and the latest reply, as Slack and Element show it. A tap
/// opens the thread.
struct ThreadSummaryButton: View {
  let thread: TimelineMessage.ThreadPreview
  let isOwn: Bool
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: 6) {
        Image(systemName: "bubble.left.and.text.bubble.right.fill")
          .foregroundStyle(SysColors.primary)
        Text(thread.replyCount == 1 ? "1 reply" : "\(thread.replyCount) replies")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.primary)
          .contentTransition(.numericText(value: Double(thread.replyCount)))
        if let latest = latestLine {
          Text(latest)
            .textStyle(TextStyles.bodySmall)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(SysColors.textSecondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(SysColors.surface, in: Capsule())
      .overlay(Capsule().strokeBorder(SysColors.primary.opacity(0.25), lineWidth: 1))
    }
    .buttonStyle(PressScaleButtonStyle())
    .padding(.leading, isOwn ? 0 : 40)
    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: thread)
    .transition(
      .scale(scale: 0.6, anchor: isOwn ? .topTrailing : .topLeading).combined(with: .opacity)
    )
    .accessibilityLabel(thread.replyCount == 1 ? "1 reply" : "\(thread.replyCount) replies")
    .accessibilityHint("Opens the thread")
  }

  private var latestLine: String? {
    guard let text = thread.latestText, !text.isEmpty else { return nil }
    guard let sender = thread.latestSenderName, !sender.isEmpty else { return text }
    return "\(sender): \(text)"
  }
}

/// The room's threads, as Element and Slack list them: who started each, its first line, and the latest reply. A tap
/// opens the thread over the room.
struct ThreadsListSheet: View {
  let viewModel: RoomViewModel
  let open: (String) -> Void

  @State private var threads: [ThreadListEntry]?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if let threads {
          if threads.isEmpty {
            ContentUnavailableView(
              "No Threads", systemImage: "bubble.left.and.text.bubble.right",
              description: Text("Long-press a message and choose Reply in Thread to start one."))
          } else {
            List(threads) { thread in
              Button {
                open(thread.rootEventId)
              } label: {
                row(thread)
              }
              .buttonStyle(.plain)
            }
            .listStyle(.plain)
          }
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .animation(.easeInOut(duration: 0.25), value: threads)
      .navigationTitle("Threads")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task { threads = await viewModel.loadThreads() }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func row(_ thread: ThreadListEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(thread.rootSenderName).textStyle(TextStyles.labelLarge)
        Spacer()
        Text(thread.latestDate, format: .relative(presentation: .named))
          .textStyle(TextStyles.labelSmall)
          .foregroundStyle(SysColors.textSecondary)
      }
      Text(thread.rootText ?? " ")
        .textStyle(TextStyles.bodyMedium)
        .lineLimit(2)
      HStack(spacing: 6) {
        Image(systemName: "bubble.left.and.text.bubble.right.fill")
          .foregroundStyle(SysColors.primary)
        Text(thread.replyCount == 1 ? "1 reply" : "\(thread.replyCount) replies")
          .foregroundStyle(SysColors.primary)
        if let latest = thread.latestText {
          Text("\(thread.latestSenderName.map { "\($0): " } ?? "")\(latest)")
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
      }
      .textStyle(TextStyles.labelMedium)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
