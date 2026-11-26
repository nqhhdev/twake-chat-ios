/// Why a message cannot be decrypted, as far as the SDK knows; the room explains it with the web client's wording
/// (`undecryptableHelpKey`).
public enum UndecryptableReason: Sendable, Equatable {
  /// No cause is known: the key may still arrive.
  case unknown
  /// Sent before the user joined the room, so no key was ever shared with them.
  case sentBeforeJoining
  /// The sender did not share the key with this device.
  case withheld
  case withheldFromUnverifiedDevice
  /// The sender's device or identity cannot be trusted.
  case untrustedSender
  /// Sent before this device existed, and the key backup does not hold its key.
  case historical
  /// Sent before this device existed; the backup may hold its key once this device is verified.
  case historicalUnverified

  /// The help under the message. `isDeviceVerified` matters only where a key may still come: an unverified device is
  /// told to verify, a verified one that no key has reached it.
  public func help(isDeviceVerified: Bool) -> String {
    switch self {
    case .sentBeforeJoining:
      "This message was sent before you joined this chat, so no key exists for it."
    case .withheld: "The sender did not share the key for this message with this device."
    case .withheldFromUnverifiedDevice:
      isDeviceVerified
        ? "The sender did not share the key for this message with this device."
        : "Verify this device with your recovery key to read it."
    case .untrustedSender:
      "The device of the sender cannot be trusted, so this message stays hidden."
    case .historical:
      "This message was sent before this device existed, and your backup does not hold its key."
    case .historicalUnverified: "Verify this device with your recovery key to read it."
    case .unknown:
      isDeviceVerified
        ? "No key for this message has reached this device. It was probably sent before this device could receive it."
        : "Verify this device with your recovery key to read it."
    }
  }
}
