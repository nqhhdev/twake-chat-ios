import Foundation

/// How a room notifies the user, as the Flutter notification settings name the choices.
public enum NotificationMode: Sendable, Equatable, CaseIterable {
  case allMessages
  case mentionsAndKeywords
  case mute
}

/// Whether the user's encryption keys are backed up with a recovery key (`m.secret_storage`), as the SDK reports it.
public enum RecoveryStatus: Sendable, Equatable {
  /// Not known yet: the client is still setting up encryption.
  case unknown
  /// Keys are backed up and this device holds them.
  case enabled
  /// No recovery is set up for this account.
  case disabled
  /// Recovery is set up, but this device lacks the keys: enter the recovery key to read older encrypted messages.
  case incomplete
}

public enum SettingsError: Error, Sendable, Equatable {
  case notSignedIn
  /// The recovery key does not match the account's backup.
  case wrongRecoveryKey
  /// The e-mail or phone is already linked to an account.
  case addressInUse
  /// The link in the confirmation e-mail was not opened yet.
  case addressNotConfirmed
  case requestFailed
  case wrongCode
  case phoneNotSupported
}

/// What the Settings tab needs about the signed-in account: its display name, its encryption recovery, and its default
/// notification modes. Implemented in MatrixData; no SDK type appears here (ADR 0006).
public protocol AccountSettingsRepository: Sendable {
  /// The user's display name from the server, or `nil` when the profile has none. Throws when it cannot be read, so a
  /// failed request is not mistaken for a profile without a name.
  func displayName() async throws(SettingsError) -> String?
  /// The user's own picture, or `nil`.
  func avatar() async -> MediaReference?
  /// The people the user blocked (Matrix "ignored users"), by name.
  func blockedUsers() async throws(SettingsError) -> [BlockedUser]
  /// Unblocks someone: their messages and invitations show again.
  func unblock(userId: String) async throws(SettingsError)
  /// Changes the user's display name, as others see it.
  func setDisplayName(_ name: String) async throws(SettingsError)
  /// Uploads a picture and makes it the user's avatar.
  func setAvatar(_ picture: PictureUpload) async throws(SettingsError)
  /// Removes the user's avatar; others see their initials.
  func removeAvatar() async throws(SettingsError)

  func recoveryStatus() async -> RecoveryStatus

  /// Restores the keys from the backup with the recovery key, so older encrypted messages can be read.
  func recover(recoveryKey: String) async throws(SettingsError)

  /// Sets up key backup and recovery, and returns the new recovery key to show the user once.
  func enableRecovery() async throws(SettingsError) -> String

  /// The mode new rooms of this kind use unless the user sets one for the room.
  func defaultNotificationMode(isDirect: Bool) async -> NotificationMode

  func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)

  /// Do not disturb: every notification of the account is off (the `.m.rule.master` push rule is enabled).
  func isDoNotDisturbOn() async -> Bool

  /// Turns do not disturb on or off, for every device of the account.
  func setDoNotDisturb(_ on: Bool) async throws(SettingsError)

  /// Starts resetting the user's cryptographic identity (new cross-signing keys; other devices and people must verify
  /// again). Returns what the server needs to allow it.
  func startIdentityReset() async throws(SettingsError) -> IdentityResetStep

  /// Finishes the reset started: with the account password, or with none after approving it on the web page.
  func finishIdentityReset(password: String?) async throws(SettingsError)

  /// Gives up the reset started.
  func cancelIdentityReset() async

  /// The e-mail addresses and phone numbers linked to the account (`GET /account/3pid`), as people find the user.
  func linkedAddresses() async -> [LinkedAddress]

  /// Who sees the user's e-mail and phone in the Twake address book (ToM `user_info/{id}/visibility`), or `nil` when
  /// the server has no ToM or did not answer.
  func contactsVisibility() async -> ContactsVisibility?

  func commonSettingsLanguage() async -> String?

  /// Changes who sees the user's e-mail and phone; both follow the one choice.
  func setContactsVisibility(_ visibility: ContactsVisibility) async throws(SettingsError)

  /// Whether the server lets the user add and remove e-mails and phones (the `m.3pid_changes` capability).
  func canChangeLinkedAddresses() async -> Bool

  /// Sends a confirmation link to `email` (`POST /account/3pid/email/requestToken`); the server e-mails it.
  func sendEmailConfirmation(to email: String) async throws(SettingsError) -> PendingEmailLink

  /// Links the e-mail once the user opened the link (`POST /account/3pid/add`). Returns `nil` when done, or the
  /// confirmation the server asks for first (User-Interactive Authentication); call again with `auth` to finish.
  func linkEmail(_ pending: PendingEmailLink, auth: DeviceAuth?) async throws(SettingsError)
    -> DeviceAuthChallenge?

  func sendPhoneConfirmation(to number: String, regionCode: String?) async throws(SettingsError)
    -> PendingPhoneLink

  func confirmPhone(_ pending: PendingPhoneLink, code: String) async throws(SettingsError)

  func linkPhone(_ pending: PendingPhoneLink, auth: DeviceAuth?) async throws(SettingsError)
    -> DeviceAuthChallenge?

  /// Unlinks an e-mail or phone from the account (`POST /account/3pid/delete`).
  func removeLinkedAddress(_ address: LinkedAddress) async throws(SettingsError)

  /// The space the cached messages and media take on the device, in bytes; `nil` when unknown.
  func cacheSize() async -> Int?

  /// Empties the cached messages and media; they load again from the server. Keys and the session stay.
  func clearCache() async throws(SettingsError)

  /// The user's status message (Matrix presence `status_msg`), or `nil`.
  func statusMessage() async -> String?

  /// Sets the status message others see; empty clears it.
  func setStatusMessage(_ message: String) async throws(SettingsError)
}

extension AccountSettingsRepository {
  public func isDoNotDisturbOn() async -> Bool { false }
  public func setDoNotDisturb(_ on: Bool) async throws(SettingsError) { throw .requestFailed }
  public func startIdentityReset() async throws(SettingsError) -> IdentityResetStep {
    throw .requestFailed
  }
  public func finishIdentityReset(password: String?) async throws(SettingsError) {
    throw .requestFailed
  }
  public func cancelIdentityReset() async {}
  public func linkedAddresses() async -> [LinkedAddress] { [] }
  public func contactsVisibility() async -> ContactsVisibility? { nil }
  public func commonSettingsLanguage() async -> String? { nil }
  public func setContactsVisibility(_ visibility: ContactsVisibility) async throws(SettingsError) {
    throw .requestFailed
  }
  public func canChangeLinkedAddresses() async -> Bool { false }
  public func sendEmailConfirmation(to email: String) async throws(SettingsError)
    -> PendingEmailLink
  {
    throw .requestFailed
  }
  public func linkEmail(_ pending: PendingEmailLink, auth: DeviceAuth?) async throws(SettingsError)
    -> DeviceAuthChallenge?
  {
    throw .requestFailed
  }
  public func removeLinkedAddress(_ address: LinkedAddress) async throws(SettingsError) {
    throw .requestFailed
  }
  public func sendPhoneConfirmation(to number: String, regionCode: String?)
    async throws(SettingsError) -> PendingPhoneLink
  {
    throw .phoneNotSupported
  }
  public func confirmPhone(_ pending: PendingPhoneLink, code: String) async throws(SettingsError) {
    throw .requestFailed
  }
  public func linkPhone(_ pending: PendingPhoneLink, auth: DeviceAuth?) async throws(SettingsError)
    -> DeviceAuthChallenge?
  {
    throw .requestFailed
  }
  public func cacheSize() async -> Int? { nil }
  public func clearCache() async throws(SettingsError) { throw .requestFailed }
  public func statusMessage() async -> String? { nil }
  public func setStatusMessage(_ message: String) async throws(SettingsError) {
    throw .requestFailed
  }
}

/// Someone the user blocked.
public struct BlockedUser: Sendable, Equatable, Identifiable {
  /// The Matrix user id.
  public let id: String
  public let displayName: String?

  public init(id: String, displayName: String?) {
    self.id = id
    self.displayName = displayName
  }

  /// The name shown, or the Matrix id when there is none.
  public var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id }
}

/// What resetting the identity needs from the user (Element X `ResetIdentity`).
public enum IdentityResetStep: Sendable, Equatable {
  /// Nothing: it is done.
  case done
  /// The account password (User-Interactive Authentication).
  case password
  /// Approval on the account's web page (OIDC account management), then finishing without a password.
  case webApproval(URL)
}

/// An e-mail address or phone number linked to the account (a Matrix third-party identifier).
public struct LinkedAddress: Sendable, Equatable, Hashable, Identifiable {
  public enum Kind: Sendable, Equatable, Hashable {
    case email
    case phone
  }

  public let kind: Kind
  public let address: String
  public var id: String { address }

  public init(kind: Kind, address: String) {
    self.kind = kind
    self.address = address
  }

  /// The `threepids` of the answer; a medium other than e-mail or phone is left out.
  public static func addresses(fromJSON data: Data?) -> [LinkedAddress] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = object["threepids"] as? [[String: Any]]
    else { return [] }
    return list.compactMap { entry in
      guard let address = entry["address"] as? String else { return nil }
      switch entry["medium"] as? String {
      case "email": return LinkedAddress(kind: .email, address: address)
      case "msisdn": return LinkedAddress(kind: .phone, address: "+" + address)
      default: return nil
      }
    }
  }
}

/// An e-mail waiting for the user to open the link the server sent: the ids the server needs to link it.
public struct PendingEmailLink: Sendable, Equatable {
  public let email: String
  /// The secret this app made for the confirmation; it is only sent back to the homeserver.
  public let clientSecret: String
  /// The server's id of the confirmation.
  public let sessionId: String

  public init(email: String, clientSecret: String, sessionId: String) {
    self.email = email
    self.clientSecret = clientSecret
    self.sessionId = sessionId
  }
}

public struct PendingPhoneLink: Sendable, Equatable {
  public let phone: String
  public let clientSecret: String
  public let sessionId: String
  public let submitURL: URL

  public init(phone: String, clientSecret: String, sessionId: String, submitURL: URL) {
    self.phone = phone
    self.clientSecret = clientSecret
    self.sessionId = sessionId
    self.submitURL = submitURL
  }
}

/// Who sees the user's e-mail and phone (web D78, Flutter `settings_contacts_visibility`); the raw values are ToM's.
public enum ContactsVisibility: String, Sendable, Equatable, CaseIterable {
  case nobody = "private"
  case contacts
  case everyone = "public"
}
