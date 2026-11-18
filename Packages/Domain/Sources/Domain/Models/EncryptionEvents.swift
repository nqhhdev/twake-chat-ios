import Foundation

extension Notification.Name {
  /// Posted after the user restores encryption keys, so open timelines retry decrypting events that were UTD.
  public static let encryptionKeysImported = Notification.Name("TwakeChat.encryptionKeysImported")
}
