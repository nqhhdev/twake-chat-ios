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
  public static let newChat = NewChat()
  public static let newSpace = NewSpace()
  public static let space = Space()
  public static let folderEditor = FolderEditor()

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
    public let newChat = "chatList.newChat"
    public let more = "chatList.more"
    public let newSpace = "chatList.newSpace"
    public let newFolder = "chatList.newFolder"
    public func filter(_ title: String) -> String { "chatList.filter.\(title)" }
    public func folder(_ name: String) -> String { "chatList.folder.\(name)" }
  }

  public struct Room: Sendable {
    public let composer = "room.composer"
    public let send = "room.send"
    public let callButton = "room.call"
    /// A row of the message actions menu, by its English title ("Reply", "Edit", "Delete"…).
    public func action(_ title: String) -> String { "room.action.\(title)" }
    /// A reaction of the quick reaction bar, by its emoji.
    public func reaction(_ key: String) -> String { "room.reaction.\(key)" }
    public let attach = "room.attach"
    public let pastePicture = "room.attach.pastePicture"
    public let sendAttachments = "room.attach.send"
    public let attachmentCaption = "room.attach.caption"
  }

  public struct Settings: Sendable {
    public let displayName = "settings.displayName"
    public let logout = "settings.logout"
    public let confirmLogout = "settings.confirmLogout"
    public let personalQR = "settings.personalQR"
  }

  public struct NewChat: Sendable {
    public let groupName = "newChat.groupName"
    public let create = "newChat.create"
    public func person(_ userId: String) -> String { "newChat.person.\(userId)" }
  }

  public struct NewSpace: Sendable {
    public let name = "newSpace.name"
    public let create = "newSpace.create"
  }

  public struct Space: Sendable {
    public let add = "space.add"
    public let newSubspace = "space.newSubspace"
    public func child(_ name: String) -> String { "space.child.\(name)" }
  }

  public struct FolderEditor: Sendable {
    public let name = "folderEditor.name"
    public let save = "folderEditor.save"
  }
}
