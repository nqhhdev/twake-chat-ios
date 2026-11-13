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

  public init(viewModel: RoomViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        PinnedBanner(viewModel: viewModel)
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
    .overlay(alignment: .top) {
      if let toast = viewModel.toast { Toast(text: toast) }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.toast)
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.pinned)
    .sensoryFeedback(.success, trigger: viewModel.toast) { _, new in new != nil }
    .navigationTitle(viewModel.roomName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // As in the Flutter chat, the header opens the chat details.
      ToolbarItem(placement: .principal) {
        Button {
          details = viewModel.makeDetails()
        } label: {
          HStack(spacing: 8) {
            TwakeAvatar(name: viewModel.roomName, size: 32)
            Text(viewModel.roomName).textStyle(TextStyles.titleMedium).lineLimit(1)
          }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the chat details")
      }
    }
    .navigationDestination(item: $details) { details in RoomDetailsScreen(viewModel: details) }
    .task(id: viewModel.roomId) { await viewModel.start() }
  }

  @ViewBuilder private func timeline(bubbleWidth: CGFloat) -> some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded:
      TimelineScroll(viewModel: viewModel, bubbleWidth: bubbleWidth)
    }
  }
}

/// The scrolling timeline. New messages spring in from the bottom and the view follows them while the user is at the
/// bottom; scrolled up, a button brings the user back down, as in Telegram and iMessage.
struct TimelineScroll: View {
  let viewModel: RoomViewModel
  let bubbleWidth: CGFloat

  @State private var position = ScrollPosition(edge: .bottom)
  @State private var isAtBottom = true

  var body: some View {
    let rows = viewModel.rows
    ScrollView {
      LazyVStack(spacing: 0) {
        if !viewModel.reachedStart {
          ProgressView()
            .padding()
            .onAppear { Task { await viewModel.loadOlder() } }
        }
        if !rows.contains(where: Self.isMessage) {
          Text("No message here yet")
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
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
    }
    .scrollPosition($position)
    // Open on the newest message, and stay on it as messages arrive or pictures load.
    .defaultScrollAnchor(.bottom)
    .defaultScrollAnchor(.bottom, for: .sizeChanges)
    .scrollDismissesKeyboard(.interactively)
    .onScrollGeometryChange(for: Bool.self) { geometry in
      // The visible rect accounts for the insets (the composer, the safe area), unlike the bare content offset.
      geometry.visibleRect.maxY >= geometry.contentSize.height - 80
    } action: { _, atBottom in
      withAnimation(.easeOut(duration: 0.2)) { isAtBottom = atBottom }
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
        }
        .accessibilityLabel("Scroll to the latest message")
        .padding(16)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
      }
    }
  }

  private static func isMessage(_ row: ChatRow) -> Bool {
    if case .other = row { false } else { true }
  }

  /// A new bubble grows from its sender's side and rises a little; other rows fade in.
  private static func insertion(for row: ChatRow) -> AnyTransition {
    let isOwn: Bool? =
      switch row {
      case .message(let model): model.message.isOwn
      case .album(let model): model.messages.first?.isOwn
      case .other: nil
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
    switch row {
    case .message(let model):
      MessageRow(
        message: model.message, position: model.position, bubbleWidth: bubbleWidth,
        viewModel: viewModel)
    case .album(let model):
      MessageRow(
        message: model.messages[model.messages.count - 1], position: model.position,
        bubbleWidth: bubbleWidth,
        viewModel: viewModel, album: model)
    case .other(let item):
      OtherRow(item: item)
    }
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
/// leading edge to reply, double-tap it to send ❤️, long-press it for the Flutter message menu.
struct MessageRow: View {
  let message: TimelineMessage
  let position: GroupPosition
  let bubbleWidth: CGFloat
  let viewModel: RoomViewModel
  var album: AlbumRowModel?

  /// How far the bubble is dragged for swipe-to-reply.
  @State private var swipe: CGFloat = 0
  @State private var didReachReply = false
  @State private var heartBurst = 0
  @State private var isForwarding = false

  /// The swipe that triggers a reply, as Telegram's.
  private static let replyThreshold: CGFloat = 56

  var body: some View {
    VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
      HStack(alignment: .bottom, spacing: 8) {
        if !message.isOwn {
          // The avatar sits by the last bubble of a group; the others keep its space so the bubbles line up.
          if position.isLast {
            TwakeAvatar(name: message.senderName, size: 32)
          } else {
            Color.clear.frame(width: 32, height: 1)
          }
        }
        Group {
          if message.isEmojiOnly, message.reply == nil { bigEmoji } else { bubble }
        }
        .overlay { HeartBurst(trigger: heartBurst) }
        .sheet(isPresented: $isForwarding) { ForwardSheet(message: message, viewModel: viewModel) }
      }
      .offset(x: swipe)
      .background(alignment: .trailing) { replyHint }
      .simultaneousGesture(swipeToReply)
      if !message.reactions.isEmpty { reactions }
    }
    .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
    .padding(.top, position.isFirst ? 8 : 2)
    .sensoryFeedback(.impact(weight: .light), trigger: didReachReply) { _, reached in reached }
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
      guard message.eventId != nil else { return }
      heartBurst += 1
      Task { await viewModel.toggleReaction("❤️", on: message) }
    }
    .contextMenu { menu }
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
      if let reply = message.reply {
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
      }
      if let album {
        AlbumGrid(album: album, width: contentWidth, viewModel: viewModel)
        if let caption = album.caption { captionText(caption) }
      } else if let media = message.media {
        MessageMediaView(message: message, media: media, width: contentWidth, viewModel: viewModel)
        if let caption = Self.caption(of: message.body) { captionText(caption) }
      } else {
        MessageBody(content: message.body)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
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
      message.isOwn ? SysColors.primaryContainer : SysColors.onPrimary,
      in: TwakeBubbleShape(isOwn: message.isOwn, isFirst: position.isFirst, isLast: position.isLast)
    )
    .shadow(color: .black.opacity(message.isOwn ? 0 : 0.10), radius: 1, y: 0.5)
    .contentShape(.contextMenuPreview, TwakeBubbleShape(isOwn: message.isOwn))
    .onTapGesture(count: 2) {
      // Double-tap sends ❤️, as a tapback; pictures keep the single tap that opens them.
      guard message.media == nil, message.eventId != nil else { return }
      heartBurst += 1
      Task { await viewModel.toggleReaction("❤️", on: message) }
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: heartBurst)
    .contextMenu { menu }
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

  /// Sending, sent and failed swap with the symbol replace effect.
  private var sendStateIcon: some View {
    let symbol =
      switch message.sendState {
      case .sent: "checkmark"
      case .sending: "clock"
      case .failed: "exclamationmark.circle"
      }
    return Image(systemName: symbol)
      .foregroundStyle(message.sendState == .failed ? SysColors.error : SysColors.textSecondary)
      .contentTransition(.symbolEffect(.replace))
      .animation(.default, value: message.sendState)
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
        .transition(.scale(scale: 0.3).combined(with: .opacity))
        .sensoryFeedback(.selection, trigger: reaction.includesOwn)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: message.reactions)
    .padding(.leading, message.isOwn ? 0 : 40)
  }

  @ViewBuilder private var menu: some View {
    // A menu row holds three items, so the six quick reactions are two rows.
    ForEach([0, 3], id: \.self) { start in
      ControlGroup {
        ForEach(RoomViewModel.quickReactions[start..<start + 3], id: \.self) { key in
          Button(key) { Task { await viewModel.toggleReaction(key, on: message) } }
        }
      }
    }
    if message.eventId != nil {
      Button("Reply", systemImage: "arrowshape.turn.up.left") { viewModel.reply(to: message) }
    }
    if let text = RoomViewModel.text(of: message.body) {
      Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
    }
    if message.eventId != nil {
      Button("Forward", systemImage: "arrowshape.turn.up.right") { isForwarding = true }
      Button(
        viewModel.isPinned(message) ? "Unpin" : "Pin",
        systemImage: viewModel.isPinned(message) ? "pin.slash" : "pin"
      ) { Task { await viewModel.togglePin(message) } }
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
