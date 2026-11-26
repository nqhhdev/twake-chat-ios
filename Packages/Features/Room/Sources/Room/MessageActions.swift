import DesignSystem
import Domain
import SwiftUI

/// The message a long press lifted, with where its row sits on screen, so the actions layer can draw it in place.
public struct MessageFocus: Equatable {
  let message: TimelineMessage
  let position: GroupPosition
  let isRead: Bool
  let album: AlbumRowModel?
  /// The row's frame in the global coordinate space.
  let frame: CGRect
}

/// Where a row last sat on screen. A plain box, not observed: scrolling updates it without redrawing the row.
final class FrameBox {
  var frame: CGRect = .zero
}

/// The long-press layer, as iMessage draws it: the chat blurs and dims, the pressed bubble lifts in place, the tapback
/// bar of quick reactions sits above it and the actions below it, both on the bubble's side. A tap outside closes it.
struct MessageActionsOverlay: View {
  let focus: MessageFocus
  let bubbleWidth: CGFloat
  let viewModel: RoomViewModel
  let onForward: (TimelineMessage) -> Void
  /// Asks for a reason, then reports; for others' messages.
  var onReport: (TimelineMessage) -> Void = { _ in }
  /// Asks to confirm, then blocks the sender; for others' messages.
  var onBlock: (TimelineMessage) -> Void = { _ in }

  @State private var appeared = false
  @State private var isPickingReaction = false
  @State private var isSelectingText = false

  private static let tapbackHeight: CGFloat = 52
  private static let rowHeight: CGFloat = 44
  private static let gap: CGFloat = 8

  private var message: TimelineMessage { focus.message }
  private var side: HorizontalAlignment { message.isOwn ? .trailing : .leading }

  var body: some View {
    GeometryReader { proxy in
      let origin = proxy.frame(in: .global).origin
      let layout = layout(in: proxy.size.height, originY: origin.y)
      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(.ultraThinMaterial)
          .overlay(Color.black.opacity(0.12))
          .ignoresSafeArea()
          .opacity(appeared ? 1 : 0)
          .onTapGesture { close() }
          .accessibilityLabel("Close")
          .accessibilityAddTraits(.isButton)
        VStack(alignment: side, spacing: Self.gap) {
          tapbackBar
            .padding(.leading, message.isOwn ? 0 : 40)
            .scaleEffect(
              appeared ? 1 : 0.4, anchor: message.isOwn ? .bottomTrailing : .bottomLeading
            )
            .opacity(appeared ? 1 : 0)
          // A tall message (an album, a long text) shrinks from its top corner to fit, as iMessage does, rather than
          // being cut; the row keeps its own height so nothing stretches.
          MessageRow(
            message: message, position: focus.position, isRead: focus.isRead,
            bubbleWidth: bubbleWidth, viewModel: viewModel, album: focus.album, isPreview: true
          )
          .frame(width: focus.frame.width, height: focus.frame.height, alignment: .top)
          // The lifted copy is only a picture of the message: links and media in it do not respond.
          .allowsHitTesting(false)
          .scaleEffect(layout.previewScale, anchor: message.isOwn ? .topTrailing : .topLeading)
          .frame(width: focus.frame.width, height: layout.previewHeight, alignment: .top)
          .scaleEffect(appeared ? 1.03 : 1, anchor: message.isOwn ? .trailing : .leading)
          .shadow(color: .black.opacity(appeared ? 0.18 : 0), radius: 12, y: 4)
          actionMenu(height: layout.menuHeight, scrolls: layout.scrollsMenu)
            .padding(.leading, message.isOwn ? 0 : 40)
            .scaleEffect(appeared ? 1 : 0.6, anchor: message.isOwn ? .topTrailing : .topLeading)
            .opacity(appeared ? 1 : 0)
        }
        .frame(width: focus.frame.width, alignment: message.isOwn ? .trailing : .leading)
        .offset(x: focus.frame.minX - origin.x, y: layout.top)
      }
    }
    .sheet(isPresented: $isPickingReaction) {
      MoreReactionsSheet { key in
        isPickingReaction = false
        Task { await viewModel.toggleReaction(key, on: message) }
        close()
      }
    }
    .sheet(isPresented: $isSelectingText, onDismiss: close) {
      if let text = selectableText { SelectTextSheet(text: text) }
    }
    .onAppear {
      withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { appeared = true }
    }
    .accessibilityAddTraits(.isModal)
  }

  // MARK: Layout

  private var selectableText: AttributedString? {
    MessageBody.selectableText(of: message.body, formatted: message.formatted)
  }

  private var actions: [Action] {
    var list: [Action] = []
    if message.eventId != nil {
      list.append(
        .init(title: "Reply", icon: "arrowshape.turn.up.left") { viewModel.reply(to: message) })
    }
    if message.eventId != nil, viewModel.canOpenThreads {
      list.append(
        .init(title: "Reply in Thread", icon: "bubble.left.and.text.bubble.right") {
          viewModel.openThread(on: message)
        })
    }
    if let text = RoomViewModel.text(of: message.body) {
      list.append(.init(title: "Copy", icon: "doc.on.doc") { UIPasteboard.general.string = text })
    }
    if selectableText != nil {
      list.append(
        .init(title: "Select Text", icon: "selection.pin.in.out", keepsLayerOpen: true) {
          isSelectingText = true
        })
    }
    if message.eventId != nil {
      list.append(.init(title: "Forward", icon: "arrowshape.turn.up.right") { onForward(message) })
      if message.media != nil {
        list.append(
          .init(title: "Share", icon: "square.and.arrow.up") {
            Task { await viewModel.share(focus.album?.messages ?? [message]) }
          })
      }
      let media = focus.album?.messages ?? [message]
      if RoomViewModel.canSaveToPhotos(media) {
        list.append(
          .init(title: "Save to Photos", icon: "square.and.arrow.down") {
            Task { await viewModel.saveToPhotos(media) }
          })
      }
      list.append(.init(title: "Copy Link", icon: "link") { viewModel.copyLink(to: message) })
      if viewModel.canSave {
        let saved = viewModel.isSaved(message)
        list.append(
          .init(title: saved ? "Unsave" : "Save", icon: saved ? "bookmark.slash" : "bookmark") {
            Task { await viewModel.toggleSaved(message) }
          })
      }
      list.append(
        .init(title: "Select", icon: "checkmark.circle") { viewModel.startSelecting(message) })
      let pinned = viewModel.isPinned(message)
      list.append(
        .init(title: pinned ? "Unpin" : "Pin", icon: pinned ? "pin.slash" : "pin") {
          Task { await viewModel.togglePin(message) }
        })
    }
    if viewModel.canTranscribe(message) {
      list.append(
        .init(title: "Transcribe", icon: "text.quote") {
          Task { await viewModel.transcribe(message) }
        })
    } else if case .transcribed = viewModel.transcription(of: message) {
      list.append(
        .init(title: "Hide Transcription", icon: "text.badge.minus") {
          viewModel.hideTranscription(of: message)
        })
    }
    if viewModel.canTranslate(message) {
      list.append(.init(title: "Translate", icon: "translate") { viewModel.translate(message) })
    } else if case .translated = viewModel.translation(of: message) {
      list.append(
        .init(title: "Show Original", icon: "arrow.uturn.backward") {
          viewModel.showOriginal(message)
        })
    }
    if message.isOwn, case .text = message.body {
      list.append(.init(title: "Edit", icon: "pencil") { viewModel.edit(message) })
    }
    if message.isOwn, message.eventId != nil {
      list.append(.init(title: "Seen by", icon: "eye") { viewModel.showReaders(of: message) })
    }
    if message.isEdited, message.eventId != nil {
      list.append(
        .init(title: "Edit History", icon: "clock.arrow.circlepath") {
          viewModel.historyMessage = message
        })
    }
    if message.eventId != nil {
      list.append(
        .init(title: "Message Info", icon: "info.circle") { viewModel.infoMessage = message })
    }
    if viewModel.canEndPoll(message) {
      list.append(
        .init(title: "End Poll", icon: "checkmark.circle") {
          Task { await viewModel.endPoll(message) }
        })
    }
    if viewModel.canDelete(message) {
      list.append(
        .init(title: "Delete", icon: "trash", isDestructive: true) {
          Task { await viewModel.delete(message) }
        })
    }
    if !message.isOwn, message.eventId != nil {
      list.append(.init(title: "Report", icon: "exclamationmark.bubble") { onReport(message) })
      list.append(
        .init(title: "Block", icon: "hand.raised", isDestructive: true) { onBlock(message) })
    }
    return list
  }

  /// Where the layer's parts go on a screen `height` tall.
  struct Layout {
    let previewScale: CGFloat
    let previewHeight: CGFloat
    let menuHeight: CGFloat
    let scrollsMenu: Bool
    let top: CGFloat
  }

  /// The menu takes at most about half the screen and scrolls past that; the bubble shrinks to what is left; the stack
  /// starts where the tapback bar sits above the bubble, moved just enough to stay on screen, as iMessage moves a
  /// bubble near an edge.
  private func layout(in height: CGFloat, originY: CGFloat) -> Layout {
    Self.layout(
      rowTop: focus.frame.minY - originY, rowHeight: focus.frame.height, screenHeight: height,
      actionCount: actions.count)
  }

  /// The layout of a row at `rowTop` (in the layer's space) and `rowHeight` tall, with `actionCount` actions.
  static func layout(
    rowTop: CGFloat, rowHeight: CGFloat, screenHeight height: CGFloat, actionCount: Int
  ) -> Layout {
    let fullMenu = CGFloat(actionCount) * Self.rowHeight
    let menu = min(fullMenu, max(Self.rowHeight * 3, height * 0.45))
    let room = height - tapbackHeight - menu - 4 * gap
    let scale = min(1, max(0.3, room / max(rowHeight, 1)))
    let preview = rowHeight * scale
    let total = tapbackHeight + preview + menu + 2 * gap
    let natural = rowTop - tapbackHeight - gap
    return Layout(
      previewScale: scale, previewHeight: preview, menuHeight: menu, scrollsMenu: menu < fullMenu,
      top: max(gap, min(natural, height - total - gap)))
  }

  // MARK: Parts

  private var tapbackBar: some View {
    HStack(spacing: 2) {
      // Any other emoji, as iMessage's "+".
      let more = Button {
        isPickingReaction = true
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(SysColors.textSecondary)
          .frame(width: 42, height: 42)
          .background(SysColors.surface, in: Circle())
      }
      .buttonStyle(PressScaleButtonStyle())
      .accessibilityLabel("More reactions")
      ForEach(viewModel.reactionBar, id: \.self) { key in
        let isMine = message.reactions.contains { $0.key == key && $0.includesOwn }
        Button {
          Task { await viewModel.toggleReaction(key, on: message) }
          close()
        } label: {
          Text(key)
            .font(.system(size: 26))
            .frame(width: 42, height: 42)
            .background(SysColors.primary.opacity(isMine ? 0.18 : 0), in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(isMine ? "Remove \(key)" : "React \(key)")
        .accessibilityIdentifier(A11yIdentifiers.room.reaction(key))
      }
      more
    }
    .padding(.horizontal, 6)
    .frame(height: Self.tapbackHeight)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
    .disabled(message.eventId == nil)
  }

  /// The actions; when they do not all fit, the list scrolls inside its card.
  @ViewBuilder private func actionMenu(height: CGFloat, scrolls: Bool) -> some View {
    if scrolls {
      ScrollView { actionRows }
        .scrollIndicators(.visible)
        .frame(width: 240, height: height)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    } else {
      actionRows
        .frame(width: 240)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
  }

  private var actionRows: some View {
    VStack(spacing: 0) {
      ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
        if index > 0 { Divider().padding(.leading, 16) }
        Button {
          if !action.keepsLayerOpen { close() }
          action.perform()
        } label: {
          HStack {
            Text(action.title)
            Spacer(minLength: 16)
            Image(systemName: action.icon)
          }
          .textStyle(TextStyles.bodyLarge)
          .foregroundStyle(action.isDestructive ? SysColors.error : SysColors.onSurface)
          .padding(.horizontal, 16)
          .frame(height: Self.rowHeight)
          .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .accessibilityIdentifier(A11yIdentifiers.room.action(action.title))
      }
    }
  }

  private func close() {
    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { viewModel.focus = nil }
  }

  struct Action {
    let title: String
    let icon: String
    var isDestructive = false
    /// The action shows a sheet over the layer, which closes the layer itself when it goes.
    var keepsLayerOpen = false
    let perform: @MainActor () -> Void
  }
}

/// A menu row darkens while pressed, as iOS menus do.
struct MenuRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
  }
}

/// The message a sheet forwards; one sheet is one value.
struct ForwardItem: Identifiable {
  let messages: [TimelineMessage]
  let id = UUID()

  init(message: TimelineMessage) { messages = [message] }
  init(messages: [TimelineMessage]) { self.messages = messages }
}

/// Any emoji as a reaction, as iMessage's "+" offers: a grid of the common ones, grouped as the emoji keyboard is.
struct MoreReactionsSheet: View {
  let pick: (String) -> Void

  static let groups: [(String, [String])] = [
    (
      "Smileys",
      [
        "😀", "😃", "😄", "😁", "😆", "🥹", "😅", "🤣", "🙂", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘",
        "😋", "😜", "🤪", "🤔", "🤨", "😐", "🙄", "😏", "😮‍💨", "😌", "😴", "🤯", "🥳", "😎", "🤓", "😕",
        "🙁", "😳", "🥺", "😭", "😤", "😡", "🤬", "😱", "😨", "🤗", "🤭", "🫡", "🤫", "😶", "🫠", "🤐",
      ]
    ),
    ("Gestures", ["👍", "👎", "👏", "🙌", "🫶", "🤝", "🙏", "✌️", "🤞", "🤟", "👌", "🤌", "👋", "💪", "👀", "🫡"]),
    ("Hearts", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "❤️‍🔥", "💯", "✨", "🔥", "⭐️", "🎉", "✅"]),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(Self.groups, id: \.0) { group in
            Text(group.0).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
              ForEach(Array(group.1.enumerated()), id: \.offset) { _, key in
                Button {
                  pick(key)
                } label: {
                  Text(key).font(.system(size: 30)).frame(width: 44, height: 44)
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("React \(key)")
              }
            }
          }
        }
        .padding(16)
      }
      .navigationTitle("Reactions")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
  }
}
