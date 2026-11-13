import DesignSystem
import Domain
import SwiftUI

/// The Telegram-style bar under the header with the pinned message: a bar per pin on the left (the current one
/// filled), "Pinned message" and its preview. A tap shows the pin before; the text slides as it changes.
struct PinnedBanner: View {
  let viewModel: RoomViewModel

  var body: some View {
    if let message = viewModel.currentPinned {
      Button {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
          viewModel.showPreviousPinned()
        }
      } label: {
        HStack(spacing: 10) {
          VStack(spacing: 2) {
            ForEach(viewModel.pinned.indices, id: \.self) { index in
              Capsule()
                .fill(SysColors.primary.opacity(index == viewModel.pinnedIndex ? 1 : 0.3))
                .frame(width: 3)
            }
          }
          .frame(height: 34)
          VStack(alignment: .leading, spacing: 0) {
            Text(
              viewModel.pinned.count > 1
                ? "Pinned message #\(viewModel.pinnedIndex + 1)" : "Pinned message"
            )
            .textStyle(TextStyles.labelMedium)
            .foregroundStyle(SysColors.primary)
            .contentTransition(.numericText(value: Double(viewModel.pinnedIndex)))
            Text(RoomViewModel.text(of: message.body) ?? RoomViewModel.fileName(of: message))
              .textStyle(TextStyles.bodySmall)
              .foregroundStyle(SysColors.onSurface)
              .lineLimit(1)
              .id(message.eventId)
              .transition(.push(from: .bottom))
          }
          Spacer()
          Image(systemName: "pin.fill").foregroundStyle(SysColors.textSecondary).rotationEffect(
            .degrees(45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(SysColors.surface).frame(height: 1) }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .transition(.move(edge: .top).combined(with: .opacity))
      .accessibilityLabel("Pinned message")
    }
  }
}

/// A short confirmation that drops in from the top and fades away.
struct Toast: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "checkmark.circle.fill")
      .textStyle(TextStyles.labelLarge)
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.black.opacity(0.75), in: Capsule())
      .padding(.top, 8)
      .transition(.move(edge: .top).combined(with: .opacity))
  }
}

/// Pick a chat to forward a message to, with a search over the chat list.
struct ForwardSheet: View {
  let message: TimelineMessage
  let viewModel: RoomViewModel

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var rooms: [RoomSummary] {
    let all = viewModel.forwardTargets()
    let text = query.trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(text) }
  }

  var body: some View {
    NavigationStack {
      List(rooms) { room in
        Button {
          Task {
            await viewModel.forward(message, to: room)
            dismiss()
          }
        } label: {
          HStack(spacing: 12) {
            TwakeAvatar(name: room.name, size: 40)
            Text(room.name).textStyle(TextStyles.titleMedium).foregroundStyle(SysColors.onSurface)
              .lineLimit(1)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .overlay {
        if rooms.isEmpty { ContentUnavailableView.search(text: query) }
      }
      .searchable(
        text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search"
      )
      .twakeTitle("Forward to")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
