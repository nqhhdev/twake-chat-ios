import DesignSystem
import Domain
import SwiftUI

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
