import Authentication
import ChatList
import DesignSystem
import Domain
import Room
import SwiftUI

/// The signed-in screens, laid out as twake-on-matrix `AppAdaptiveScaffold` (ADR 0022). The Contacts, Chats and
/// Settings tabs switch the first column. On a phone held upright and on a folded Duo, the tabs are the Twake bottom bar
/// and a chat is pushed over them; on an unfolded Duo, an iPad or any landscape screen they are the Twake navigation
/// rail at the leading edge, and from 905 pt the first column is 472 pt beside the open chat. Folding, unfolding or
/// rotating keeps the tab and the chat. The shell joins the features, which do not know each other (ADR 0005).
struct ChatShell: View {
  enum Tab: Hashable {
    case contacts, chats, settings
  }

  let chatList: ChatListViewModel
  let signedIn: SignedInViewModel
  /// Makes a room's screen model; the closure it is given closes the room (after the user left it).
  let makeRoom: (RoomSummary, @escaping @MainActor () -> Void) -> RoomViewModel

  /// How the shell lays out a screen of `width` × `height` points (safe areas included, as Flutter measures).
  struct Layout: Equatable {
    /// The chat list beside the chat (ADR 0022).
    let isTwoColumn: Bool
    /// The navigation rail at the leading edge instead of the bottom bar: on a wide screen and on any screen on its
    /// side, where a bottom bar would take height the chat needs.
    let usesRail: Bool

    init(width: CGFloat, height: CGFloat) {
      isTwoColumn = TwakeLayout.isTwoColumn(width: width)
      usesRail = isTwoColumn || width > height
    }
  }

  @State private var tab = Tab.chats
  @State private var room: RoomViewModel?
  @State private var isRoomPushed = false

  var body: some View {
    GeometryReader { geometry in
      // Flutter's breakpoints compare the whole screen width (MediaQuery), safe areas included.
      let layout = Layout(
        width: geometry.size.width + geometry.safeAreaInsets.leading
          + geometry.safeAreaInsets.trailing,
        height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
      let isTwoColumn = layout.isTwoColumn
      let usesRail = layout.usesRail
      HStack(spacing: 0) {
        if usesRail {
          rail
          Rectangle().fill(SysColors.surface).frame(width: 1)
        }
        if isTwoColumn {
          NavigationStack { tabContent(isBesideChat: true) }
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
        } else {
          NavigationStack {
            VStack(spacing: 0) {
              tabContent(isBesideChat: false)
              if !usesRail { TwakeBottomBar(selection: $tab, items: navigationItems) }
            }
            .navigationDestination(isPresented: $isRoomPushed) {
              if let room { RoomScreen(viewModel: room).id(room.roomId) }
            }
          }
        }
      }
      .background(SysColors.background)
    }
  }

  /// Contacts, Chats and Settings (`AdaptiveDestinationEnum`); on the bottom bar Settings shows the user's avatar.
  private var navigationItems: [TwakeNavigationItem<Tab>] {
    [
      .init(value: Tab.contacts, title: "Contacts") { _ in
        Image(systemName: "person.2.circle").font(.system(size: 24))
      },
      .init(value: Tab.chats, title: "Chats") { _ in
        Image(systemName: "message.fill").font(.system(size: 22))
      },
      .init(value: Tab.settings, title: "Settings") { isSelected in
        TwakeAvatar(name: signedIn.displayName, size: 28)
          .overlay(
            Circle().strokeBorder(isSelected ? SysColors.primary : ColorToken(0), lineWidth: 2))
      },
    ]
  }

  /// On the rail Settings is a gear, and the user's avatar sits at the bottom, as in the Flutter rail.
  private var rail: some View {
    TwakeNavigationRail(
      selection: $tab,
      items: [
        navigationItems[0], navigationItems[1],
        .init(value: Tab.settings, title: "Settings") { _ in
          Image(systemName: "gearshape").font(.system(size: 22))
        },
      ]
    ) {
      Button {
        tab = .settings
      } label: {
        TwakeAvatar(name: signedIn.displayName, size: 56)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Settings")
    }
  }

  /// The selected tab. Beside the chat, the open room is highlighted in the list; on a phone the chat covers the list,
  /// so nothing is.
  @ViewBuilder private func tabContent(isBesideChat: Bool) -> some View {
    switch tab {
    case .contacts:
      ContentUnavailableView(
        "Contacts", systemImage: "person.2.circle",
        description: Text("Contacts are not available in this version yet.")
      )
      .frame(maxHeight: .infinity)
      .twakeTitle("Contacts")
    case .chats:
      ChatListScreen(
        viewModel: chatList, selectedRoomId: isBesideChat ? room?.roomId : nil, onSelect: open)
    case .settings:
      SettingsScreen(viewModel: signedIn)
    }
  }

  private func open(_ summary: RoomSummary) {
    if room?.roomId != summary.id {
      room = makeRoom(summary) { [room = $room, pushed = $isRoomPushed] in
        pushed.wrappedValue = false
        room.wrappedValue = nil
      }
    }
    isRoomPushed = true
  }
}
