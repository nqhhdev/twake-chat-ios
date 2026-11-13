import DesignSystem
import Domain
import SwiftUI

/// The Flutter chat input: a banner while replying or editing, a rounded text field that grows to a few lines, and the
/// send button, shown when there is text.
struct ComposerView: View {
  @Bindable var viewModel: RoomViewModel
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      banner
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Type a message", text: $viewModel.draft, axis: .vertical)
          .textStyle(TextStyles.bodyLarge)
          .lineLimit(1...6)
          .focused($isFocused)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(SysColors.surface, in: .rect(cornerRadius: 24))
        if viewModel.canSend {
          Button {
            Task { await viewModel.send() }
          } label: {
            Image(systemName: "paperplane.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(SysColors.onPrimary)
              .frame(width: 44, height: 44)
              .background(SysColors.primary, in: Circle())
          }
          .accessibilityLabel("Send message")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .background(SysColors.background)
    .onChange(of: viewModel.composerMode) { _, mode in
      if mode != .new { isFocused = true }
    }
  }

  @ViewBuilder private var banner: some View {
    switch viewModel.composerMode {
    case .new:
      EmptyView()
    case .reply(_, let reply):
      ComposerBanner(
        icon: "arrowshape.turn.up.left", title: "Reply to \(reply.senderName)", text: reply.text,
        cancel: viewModel.cancelComposerMode)
    case .edit:
      ComposerBanner(icon: "pencil", title: "Edit", text: nil, cancel: viewModel.cancelComposerMode)
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
      .accessibilityLabel("Cancel")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(SysColors.surface)
  }
}
