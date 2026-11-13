import DesignSystem
import Domain
import SwiftUI

/// A chat, laid out as the Flutter app's chat page: the timeline, newest at the bottom, with Twake bubbles (own
/// messages on the right), day dividers and room events as centred notices, then the composer. Bubbles are at most
/// `TwakeLayout.bubbleWidth(in:)` wide, so the chat reads the same on a phone, a folded and an unfolded Duo. It holds
/// no logic.
public struct RoomScreen: View {
  @Bindable var viewModel: RoomViewModel

  public init(viewModel: RoomViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        timeline(bubbleWidth: TwakeLayout.bubbleWidth(in: geometry.size.width))
        if let message = viewModel.errorMessage {
          Text(message)
            .textStyle(TextStyles.bodySmall)
            .foregroundStyle(SysColors.error)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        ComposerView(viewModel: viewModel)
      }
    }
    .background(SysColors.background)
    .navigationTitle(viewModel.roomName)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: viewModel.roomId) { await viewModel.start() }
  }

  @ViewBuilder private func timeline(bubbleWidth: CGFloat) -> some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded(let items):
      ScrollView {
        LazyVStack(spacing: 2) {
          if !viewModel.reachedStart {
            ProgressView()
              .padding()
              .onAppear { Task { await viewModel.loadOlder() } }
          }
          if items.allSatisfy({ if case .message = $0.kind { false } else { true } }) {
            Text("No message here yet")
              .textStyle(TextStyles.bodyMedium)
              .foregroundStyle(SysColors.textSecondary)
              .padding(.vertical, 24)
          }
          ForEach(items) { item in
            TimelineRow(item: item, bubbleWidth: bubbleWidth, viewModel: viewModel)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .defaultScrollAnchor(.bottom)
      .scrollDismissesKeyboard(.interactively)
    }
  }
}

/// One timeline row.
struct TimelineRow: View {
  let item: TimelineItem
  let bubbleWidth: CGFloat
  let viewModel: RoomViewModel

  var body: some View {
    switch item.kind {
    case .message(let message):
      MessageRow(message: message, bubbleWidth: bubbleWidth, viewModel: viewModel)
    case .dayDivider(let date):
      Text(RoomViewModel.dayTitle(date))
        .textStyle(TextStyles.labelMedium)
        .foregroundStyle(SysColors.onSurface)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(SysColors.surface, in: Capsule())
        .padding(.vertical, 8)
    case .readMarker:
      EmptyView()
    case .stateNotice(let text):
      Text(text)
        .textStyle(TextStyles.bodySmall)
        .foregroundStyle(SysColors.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    case .timelineStart:
      EmptyView()
    }
  }
}

/// A message bubble with its sender (others only), reply quote, body, time and reactions, and the Flutter message
/// menu as a context menu.
struct MessageRow: View {
  let message: TimelineMessage
  let bubbleWidth: CGFloat
  let viewModel: RoomViewModel

  var body: some View {
    VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
      HStack(alignment: .bottom, spacing: 8) {
        if !message.isOwn { TwakeAvatar(name: message.senderName, size: 32) }
        bubble
      }
      if !message.reactions.isEmpty { reactions }
    }
    .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
    .padding(.vertical, 2)
  }

  /// The widest the text inside the bubble may be: the bubble's limit less its padding and, for others, the avatar.
  private var contentWidth: CGFloat {
    bubbleWidth - 24 - (message.isOwn ? 0 : 40)
  }

  /// The bubble hugs its content: `HuggingStack` makes it as wide as its widest part, at most `contentWidth`, so a
  /// short message gets a short bubble and a long one wraps at the cap.
  private var bubble: some View {
    HuggingStack(maxWidth: contentWidth, spacing: 4) {
      if !message.isOwn {
        Text(message.senderName)
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.primary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if let reply = message.reply {
        HStack(spacing: 6) {
          Rectangle().fill(SysColors.primary).frame(width: 3)
          VStack(alignment: .leading, spacing: 0) {
            Text(reply.senderName).textStyle(TextStyles.labelMedium).foregroundStyle(
              SysColors.primary)
            Text(reply.text ?? "…").textStyle(TextStyles.bodySmall).foregroundStyle(
              SysColors.textSecondary
            )
            .lineLimit(2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      MessageBody(content: message.body)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 4) {
        if message.isEdited { Text("edited") }
        Text(message.date, format: .dateTime.hour().minute())
        if message.isOwn { sendStateIcon }
      }
      .textStyle(TextStyles.labelSmall)
      .foregroundStyle(SysColors.textSecondary)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      message.isOwn ? SysColors.primaryContainer : SysColors.onPrimary, in: .rect(cornerRadius: 20)
    )
    .shadow(color: .black.opacity(message.isOwn ? 0 : 0.12), radius: 1)
    .contextMenu { menu }
  }

  @ViewBuilder private var sendStateIcon: some View {
    switch message.sendState {
    case .sent: Image(systemName: "checkmark")
    case .sending: Image(systemName: "clock")
    case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(SysColors.error)
    }
  }

  private var reactions: some View {
    HStack(spacing: 4) {
      ForEach(message.reactions) { reaction in
        Button {
          Task { await viewModel.toggleReaction(reaction.key, on: message) }
        } label: {
          Text("\(reaction.key) \(reaction.count)")
            .textStyle(TextStyles.labelMedium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
              reaction.includesOwn ? SysColors.primaryContainer : SysColors.surface, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.leading, message.isOwn ? 0 : 40)
  }

  @ViewBuilder private var menu: some View {
    ControlGroup {
      ForEach(RoomViewModel.quickReactions, id: \.self) { key in
        Button(key) { Task { await viewModel.toggleReaction(key, on: message) } }
      }
    }
    if message.eventId != nil {
      Button("Reply", systemImage: "arrowshape.turn.up.left") { viewModel.reply(to: message) }
    }
    if let text = RoomViewModel.text(of: message.body) {
      Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
    }
    if message.isOwn, case .text = message.body {
      Button("Edit", systemImage: "pencil") { viewModel.edit(message) }
    }
    if message.isOwn, message.eventId != nil {
      Button("Delete", systemImage: "trash", role: .destructive) {
        Task { await viewModel.delete(message) }
      }
    }
  }
}

/// The content of a message, by kind.
struct MessageBody: View {
  let content: TimelineMessage.Body

  var body: some View {
    Group {
      switch content {
      case .text(let text): Text(LocalizedStringKey(text))
      case .emote(let text): Text("* \(text)").italic()
      case .notice(let text): Text(text).foregroundStyle(SysColors.textSecondary)
      case .image(let caption): Label(caption ?? "Picture", systemImage: "photo")
      case .video(let caption): Label(caption ?? "Video", systemImage: "video")
      case .audio(let caption): Label(caption ?? "Audio", systemImage: "waveform")
      case .file(let name): Label(name, systemImage: "doc")
      case .location(let text): Label(text, systemImage: "mappin.and.ellipse")
      case .sticker(let text): Text(text)
      case .poll(let question): Label(question, systemImage: "chart.bar")
      case .redacted:
        Label("This message has been deleted", systemImage: "trash").foregroundStyle(
          SysColors.textSecondary)
      case .unableToDecrypt:
        Label("This message has been encrypted", systemImage: "lock").foregroundStyle(
          SysColors.textSecondary)
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
