import DesignSystem
import Domain
import SwiftUI

/// A row in selection mode: a check circle slides in on the leading side and the whole row toggles the message, as
/// Messages and Telegram do; the row's own gestures (swipe to reply, long press, links) are off meanwhile.
struct SelectableRow<Content: View>: View {
  let message: TimelineMessage
  let viewModel: RoomViewModel
  @ViewBuilder let content: Content

  var body: some View {
    let selected = viewModel.isSelected(message)
    HStack(spacing: 8) {
      Image(systemName: selected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 22))
        .foregroundStyle(selected ? SysColors.primary : SysColors.textSecondary)
        .contentTransition(.symbolEffect(.replace))
        .padding(.leading, 12)
        .transition(.move(edge: .leading).combined(with: .opacity))
      content.allowsHitTesting(false)
    }
    .background(SysColors.primary.opacity(selected ? 0.08 : 0))
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.snappy) { viewModel.toggleSelection(message) }
    }
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

/// In place of the composer while picking messages: how many are picked, and Copy, Forward and Delete for them all.
struct MessageSelectionBar: View {
  let viewModel: RoomViewModel
  let onForward: ([TimelineMessage]) -> Void
  @State private var isConfirmingDelete = false

  var body: some View {
    let count = viewModel.selectedMessages.count
    HStack(spacing: 20) {
      Button(localized("Cancel")) { viewModel.endSelecting() }
      Spacer()
      Text(localized("\(count) selected"))
        .textStyle(TextStyles.labelLarge)
        .contentTransition(.numericText(value: Double(count)))
        .animation(.snappy, value: count)
      Spacer()
      Button(localized("Copy"), systemImage: "doc.on.doc") { viewModel.copySelection() }
        .disabled(viewModel.selectionText.isEmpty)
      Button(localized("Forward"), systemImage: "arrowshape.turn.up.right") {
        onForward(viewModel.orderedSelection)
      }
      .disabled(count == 0)
      Button(localized("Delete"), systemImage: "trash", role: .destructive) {
        isConfirmingDelete = true
      }
      .disabled(!viewModel.canDeleteSelection)
      .confirmationDialog(
        count == 1
          ? localized("Delete this message for everyone?")
          : localized("Delete \(count) messages for everyone?"),
        isPresented: $isConfirmingDelete, titleVisibility: .visible
      ) {
        Button(localized("Delete"), role: .destructive) {
          Task { await viewModel.deleteSelection() }
        }
      }
    }
    .labelStyle(.iconOnly)
    .font(.system(size: 19))
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.bar)
  }
}
