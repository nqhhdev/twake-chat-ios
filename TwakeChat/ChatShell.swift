import ChatList
import DesignSystem
import Domain
import Room
import SwiftUI

/// The signed-in screens, laid out as twake-on-matrix `AppAdaptiveScaffold`: under 905 pt wide (a phone, a folded Duo)
/// the chat list and the chat are one stack, the chat pushed over the list; from 905 pt (an unfolded Duo, an iPad) the
/// list is a 472 pt column beside the open chat. Folding or unfolding keeps the open chat. The shell joins the ChatList
/// and Room features, which do not know each other (ADR 0005).
struct ChatShell: View {
  let chatList: ChatListViewModel
  let makeRoom: (RoomSummary) -> RoomViewModel

  @State private var room: RoomViewModel?
  @State private var isRoomPushed = false

  var body: some View {
    GeometryReader { geometry in
      // Flutter's breakpoints compare the whole screen width (MediaQuery), safe areas included.
      let width =
        geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
      if TwakeLayout.isTwoColumn(width: width) {
        HStack(spacing: 0) {
          NavigationStack {
            ChatListScreen(viewModel: chatList, selectedRoomId: room?.roomId, onSelect: open)
          }
          .frame(width: TwakeLayout.listColumnWidth)
          Rectangle().fill(SysColors.surface).frame(width: 1)
          NavigationStack {
            if let room {
              RoomScreen(viewModel: room).id(room.roomId)
            } else {
              TwakeLogo(TwakeLogo.welcomeResource)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SysColors.background)
            }
          }
        }
      } else {
        NavigationStack {
          ChatListScreen(viewModel: chatList, onSelect: open)
            .navigationDestination(isPresented: $isRoomPushed) {
              if let room { RoomScreen(viewModel: room).id(room.roomId) }
            }
        }
      }
    }
  }

  private func open(_ summary: RoomSummary) {
    if room?.roomId != summary.id { room = makeRoom(summary) }
    isRoomPushed = true
  }
}
