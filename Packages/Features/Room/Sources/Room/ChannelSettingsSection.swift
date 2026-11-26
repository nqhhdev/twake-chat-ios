import DesignSystem
import Domain
import SwiftUI

struct ChannelSettingsSection: View {
  let viewModel: RoomDetailsViewModel
  let channel: ChannelSettings

  var body: some View {
    Section {
      Toggle(isOn: gifsBinding) {
        Label("GIFs", systemImage: "photo.on.rectangle.angled")
      }
      .disabled(!channel.isOwner || viewModel.isChangingChannel)
    } header: {
      Text("Channel")
    } footer: {
      Text(footer)
    }
  }

  private var gifsBinding: Binding<Bool> {
    Binding(
      get: { channel.gifsEnabled },
      set: { enabled in Task { await viewModel.setGifs(enabled) } })
  }

  private var footer: String {
    let state =
      channel.gifsEnabled
      ? "Members can send GIFs here." : "GIFs are off: the GIF picker is hidden in this chat."
    return channel.isOwner ? state : state + " Only the owner of the chat changes it."
  }
}
