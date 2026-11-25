/// The accessibility identifiers the UI tests (`TwakeChatUITests`) find screens and controls by. The app and the tests
/// share this one list, so a renamed control breaks the build rather than a test run. The shape follows
/// element-x-ios's `A11yIdentifiers` (one namespace per screen); the identifiers are Twake's own.
public enum A11yIdentifiers {
  public static let welcome = Welcome()
  public static let homeserverPicker = HomeserverPicker()
  public static let passwordLogin = PasswordLogin()
  public static let chatList = ChatList()
  public static let room = Room()
  public static let settings = Settings()

  public struct Welcome: Sendable {
    public let companyServer = "welcome.companyServer"
  }

  public struct HomeserverPicker: Sendable {
    public let server = "homeserverPicker.server"
    public let `continue` = "homeserverPicker.continue"
  }

  public struct PasswordLogin: Sendable {
    public let homeserver = "passwordLogin.homeserver"
    public let username = "passwordLogin.username"
    public let password = "passwordLogin.password"
    public let signIn = "passwordLogin.signIn"
  }

  public struct ChatList: Sendable {
    public let list = "chatList.list"
    /// A room row, by the room's display name.
    public func room(_ name: String) -> String { "chatList.room.\(name)" }
  }

  public struct Room: Sendable {
    public let composer = "room.composer"
    public let send = "room.send"
    /// A row of the message actions menu, by its English title ("Reply", "Edit", "Delete"…).
    public func action(_ title: String) -> String { "room.action.\(title)" }
    /// A reaction of the quick reaction bar, by its emoji.
    public func reaction(_ key: String) -> String { "room.reaction.\(key)" }
  }

  public struct Settings: Sendable {
    public let displayName = "settings.displayName"
    public let logout = "settings.logout"
    public let confirmLogout = "settings.confirmLogout"
    public let personalQR = "settings.personalQR"
  }
}
