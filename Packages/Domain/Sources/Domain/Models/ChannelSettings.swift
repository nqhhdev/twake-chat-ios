import Foundation

public struct ChannelSettings: Sendable, Equatable {
  public static let gifsStateType = "app.twake.chat.gifs"

  public let isOwner: Bool
  public let gifsEnabled: Bool

  public init(isOwner: Bool, gifsEnabled: Bool) {
    self.isOwner = isOwner
    self.gifsEnabled = gifsEnabled
  }

  public static func isOwner(canInvite: Bool, powerLevel: Int64) -> Bool {
    canInvite && powerLevel >= 100
  }

  public static func isEnabled(_ content: [String: Any]?) -> Bool? {
    content?["enabled"] as? Bool
  }
}
