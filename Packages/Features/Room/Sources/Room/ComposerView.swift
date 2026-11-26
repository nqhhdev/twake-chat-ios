import DesignSystem
import Domain
import SwiftUI

/// The Flutter chat input: a banner while replying or editing, a rounded text field that grows to a few lines, and the
/// send button, shown when there is text. The banner slides up, the send button pops in, bounces and taps the haptic
/// engine on each send, as in Telegram and iMessage.
struct ComposerView: View {
  @Bindable var viewModel: RoomViewModel
  @FocusState private var isFocused: Bool
  @State private var recorder = VoiceRecorder()
  @State private var selection: TextSelection?
  /// The link the « Add a link » dialog writes, with the text and address typed in it.
  @State private var link: LinkTarget?
  @State private var linkText = ""
  @State private var linkAddress = ""
  /// How far the mic is dragged to the leading side; past `cancelDistance` the recording is dropped.
  @State private var dragOffset: CGFloat = 0
  @State private var isScheduling = false
  private static let cancelDistance: CGFloat = 100

  var body: some View {
    VStack(spacing: 0) {
      let commands = viewModel.commandSuggestions
      if !commands.isEmpty {
        CommandSuggestions(commands: commands) { command in
          viewModel.pick(command)
          isFocused = true
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      let emotes = viewModel.emoteSuggestions
      if !emotes.isEmpty {
        EmoteSuggestions(emotes: emotes, viewModel: viewModel) { emote in
          viewModel.pickEmote(emote)
          isFocused = true
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      let emojis = viewModel.emojiSuggestions
      if !emojis.isEmpty {
        EmojiSuggestions(suggestions: emojis) { emoji in
          viewModel.pickEmoji(emoji)
          isFocused = true
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      let suggestions = viewModel.mentionSuggestions
      if !suggestions.isEmpty {
        MentionSuggestions(members: suggestions, viewModel: viewModel) { member in
          viewModel.pickMention(member)
          isFocused = true
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      if !viewModel.scheduled.isEmpty {
        ScheduledBanner(viewModel: viewModel)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      banner
      if let typing = viewModel.typingText {
        TypingIndicator(text: typing)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      if viewModel.uploadCount > 0 {
        ProgressView("Sending…")
          .textStyle(TextStyles.bodySmall)
          .padding(.vertical, 4)
          .transition(.opacity)
      }
      if let range = selectedRange, !recorder.isRecording {
        FormatBar { format in apply(format, to: range) }
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      HStack(alignment: .bottom, spacing: 8) {
        if recorder.isRecording {
          recordingBar
        } else {
          AttachmentButton(viewModel: viewModel)
            .transition(.scale.combined(with: .opacity))
          field
        }
        if viewModel.canSend {
          sendButton
        } else {
          micButton
        }
      }
      .padding(.horizontal, RoomMetrics.gutter)
      .padding(.vertical, 8)
    }
    .background(SysColors.background)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.canSend)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recorder.isRecording)
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.composerMode)
    .sensoryFeedback(.impact(weight: .light), trigger: viewModel.sendCount)
    .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.typingText)
    .animation(.easeInOut(duration: 0.2), value: viewModel.uploadCount)
    .animation(.easeInOut(duration: 0.2), value: selectedRange == nil)
    .onChange(of: viewModel.draft) { old, new in
      Task {
        await viewModel.draftDidChange(from: old, to: new)
        await viewModel.loadMembersIfNeeded()
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.mentionSuggestions)
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.commandSuggestions)
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.emojiSuggestions)
    .onChange(of: viewModel.composerMode) { _, mode in
      if mode != .new { isFocused = true }
    }
    .alert(
      "Microphone access is off",
      isPresented: Binding(get: { recorder.permissionDenied }, set: { _ in })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Allow Twake Chat to use the microphone in Settings to record voice messages.")
    }
    .alert(
      "Add a link",
      isPresented: Binding(get: { link != nil }, set: { if !$0 { link = nil } })
    ) {
      TextField("Text", text: $linkText)
      TextField("Address", text: $linkAddress)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Cancel", role: .cancel) {}
      Button("Add", action: addLink)
        .disabled(TextFormatting.webAddress(linkAddress) == nil)
    } message: {
      Text("The address of a web page, starting with https:// or www.")
    }
  }

  /// The selected text of the field while it is focused; `nil` for a caret or several ranges.
  private var selectedRange: Range<String.Index>? {
    guard isFocused, case .selection(let range) = selection?.indices, !range.isEmpty else {
      return nil
    }
    return range
  }

  /// Formats the selection and keeps the formatted text selected; a link opens the dialog first.
  private func apply(_ format: TextFormat, to range: Range<String.Index>) {
    guard format == .link else {
      selection = TextSelection(range: viewModel.format(format, selection: range))
      return
    }
    let target = viewModel.linkTarget(selection: range)
    linkText = target.text
    linkAddress = target.url
    link = target
  }

  private func addLink() {
    guard let target = link,
      let caret = viewModel.addLink(target, label: linkText, url: linkAddress)
    else { return }
    isFocused = true
    selection = TextSelection(insertionPoint: caret.lowerBound)
  }

  private var field: some View {
    TextField("Type a message", text: $viewModel.draft, selection: $selection, axis: .vertical)
      .textStyle(TextStyles.bodyLarge)
      .lineLimit(1...6)
      .focused($isFocused)
      .onKeyPress(keys: [.return, .upArrow, .escape], phases: .down) { press in
        guard let key = ComposerKey(press.key, modifiers: press.modifiers) else { return .ignored }
        return viewModel.handle(key) ? .handled : .ignored
      }
      .accessibilityIdentifier(A11yIdentifiers.room.composer)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(SysColors.surface, in: .rect(cornerRadius: 24))
  }

  private var sendButton: some View {
    Button {
      Task { await viewModel.send() }
    } label: {
      Image(systemName: isEditing ? "checkmark" : "paperplane.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(SysColors.onPrimary)
        .symbolEffect(.bounce, value: viewModel.sendCount)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 44, height: 44)
        .background(SysColors.primary, in: Circle())
    }
    .buttonStyle(PressScaleButtonStyle())
    .keyboardShortcut(.return, modifiers: .command)
    .contextMenu {
      if viewModel.canScheduleDraft {
        Button("Schedule Message", systemImage: "clock") { isScheduling = true }
      }
    }
    .sheet(isPresented: $isScheduling) { ScheduleSheet(viewModel: viewModel) }
    .accessibilityLabel(isEditing ? "Save the edit" : "Send message")
    .accessibilityIdentifier(A11yIdentifiers.room.send)
    .transition(.scale(scale: 0.4).combined(with: .opacity))
  }

  /// Hold to record; slide left to cancel; release to send. The button grows while recording.
  private var micButton: some View {
    Image(systemName: "mic.fill")
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(recorder.isRecording ? SysColors.onPrimary : SysColors.primary)
      .frame(width: 44, height: 44)
      .background(recorder.isRecording ? SysColors.primary : SysColors.surface, in: Circle())
      .scaleEffect(recorder.isRecording ? 1.35 + CGFloat(recorder.level) * 0.25 : 1)
      .offset(x: dragOffset)
      .animation(.easeOut(duration: 0.1), value: recorder.level)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if !recorder.isRecording, dragOffset == 0, value.translation == .zero {
              Task { await recorder.start() }
            }
            dragOffset = min(0, value.translation.width)
          }
          .onEnded { _ in
            let cancelled = -dragOffset >= Self.cancelDistance
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = 0 }
            guard let recording = recorder.stop(keep: !cancelled) else { return }
            Task {
              await viewModel.send(
                attachment: .voice(duration: recording.duration, waveform: recording.waveform),
                fileURL: recording.url, mimeType: "audio/mp4", size: nil)
              try? FileManager.default.removeItem(at: recording.url.deletingLastPathComponent())
            }
          }
      )
      .accessibilityLabel("Hold to record a voice message")
      .transition(.scale(scale: 0.4).combined(with: .opacity))
  }

  /// While recording: a pulsing red dot, the time, and "Slide to cancel", which fades as the mic slides left.
  private var recordingBar: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(SysColors.error)
        .frame(width: 10, height: 10)
        .phaseAnimator([1.0, 0.3]) { dot, opacity in
          dot.opacity(opacity)
        } animation: { _ in
          .easeInOut(duration: 0.6)
        }
      Text(AudioMessageRow.time(recorder.elapsed))
        .textStyle(TextStyles.bodyLarge)
        .monospacedDigit()
        .contentTransition(.numericText())
      Spacer()
      Label("Slide to cancel", systemImage: "chevron.left")
        .textStyle(TextStyles.bodyMedium)
        .foregroundStyle(SysColors.textSecondary)
        .opacity(1 - Double(min(1, -dragOffset / Self.cancelDistance)))
        .offset(x: dragOffset / 3)
    }
    .padding(.horizontal, 16)
    .frame(height: 44)
    .background(SysColors.surface, in: .rect(cornerRadius: 24))
    .transition(.move(edge: .trailing).combined(with: .opacity))
  }

  private var isEditing: Bool {
    if case .edit = viewModel.composerMode { true } else { false }
  }

  @ViewBuilder private var banner: some View {
    switch viewModel.composerMode {
    case .new:
      EmptyView()
    case .reply(_, let reply):
      ComposerBanner(
        icon: "arrowshape.turn.up.left", title: "Reply to \(reply.senderName)", text: reply.text,
        cancel: viewModel.cancelComposerMode
      )
      .transition(.move(edge: .bottom).combined(with: .opacity))
    case .edit:
      ComposerBanner(icon: "pencil", title: "Edit", text: nil, cancel: viewModel.cancelComposerMode)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}

private struct ComposerBanner: View {
  let icon: String
  let title: String
  let text: String?
  let cancel: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon).foregroundStyle(SysColors.primary)
      VStack(alignment: .leading, spacing: 0) {
        Text(title).textStyle(TextStyles.labelLarge).foregroundStyle(SysColors.primary)
        if let text {
          Text(text).textStyle(TextStyles.bodySmall).foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
      }
      Spacer()
      Button(action: cancel) {
        Image(systemName: "xmark").foregroundStyle(SysColors.textSecondary)
      }
      .keyboardShortcut(.cancelAction)
      .accessibilityLabel("Cancel")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(SysColors.surface)
  }
}

/// The formats of the selected text, above the field while text is selected, as Telegram offers them. Each button
/// writes its Markdown around the selection, or takes it off.
private struct FormatBar: View {
  let apply: (TextFormat) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(TextFormat.allCases, id: \.self) { format in
        Button {
          apply(format)
        } label: {
          Image(systemName: format.systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SysColors.onSurface)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(format.label)
      }
    }
    .padding(.horizontal, 8)
    .background(SysColors.surface, in: .rect(cornerRadius: 14))
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Formatting")
  }
}

/// The people matching the "@" being typed, above the composer, as Telegram and the Flutter app show them: a tap
/// writes the mention.
struct MentionSuggestions: View {
  let members: [RoomMember]
  let viewModel: RoomViewModel
  let pick: (RoomMember) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(members) { member in
        Button {
          pick(member)
        } label: {
          HStack(spacing: 10) {
            if member == .everyone {
              Image(systemName: "megaphone.fill")
                .foregroundStyle(SysColors.primary)
                .frame(width: 32, height: 32)
            } else {
              TwakeAvatar(
                name: member.name, size: 32, pictureID: member.avatar?.source,
                load: member.avatar.map { reference in
                  { @Sendable [viewModel] in await viewModel.picture(reference) }
                })
            }
            VStack(alignment: .leading, spacing: 0) {
              Text(member == .everyone ? "Notify everyone" : member.name)
                .textStyle(TextStyles.bodyMedium)
                .foregroundStyle(SysColors.onSurface)
                .lineLimit(1)
              Text(member.id)
                .textStyle(TextStyles.labelSmall)
                .foregroundStyle(SysColors.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 12)
          .frame(height: 48)
          .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .accessibilityLabel(member == .everyone ? "Notify everyone" : "Mention \(member.name)")
      }
    }
    .background(.regularMaterial, in: .rect(cornerRadius: 14))
    .clipShape(.rect(cornerRadius: 14))
    .shadow(color: .black.opacity(0.10), radius: 8, y: -2)
    .padding(.horizontal, 12)
    .padding(.bottom, 4)
  }
}

/// The bot commands the "/" word may become (MSC4332): the syntax and what it does; a tap writes its name.
struct CommandSuggestions: View {
  let commands: [BotCommand]
  let onPick: (BotCommand) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(commands) { command in
        Button {
          onPick(command)
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "terminal")
              .foregroundStyle(SysColors.primary)
              .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
              Text("/" + command.syntax)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(SysColors.onSurface)
              if !command.description.isEmpty {
                Text(command.description)
                  .font(.caption)
                  .foregroundStyle(SysColors.textSecondary)
                  .lineLimit(1)
              }
            }
            Spacer()
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .background(.bar)
  }
}
