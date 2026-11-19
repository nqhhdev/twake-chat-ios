import Domain
import Foundation

/// A hand-written `AccountSettingsRepository` for tests (ADR 0010).
public final class FakeAccountSettingsRepository: AccountSettingsRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _displayName: String?
  private var _status: RecoveryStatus = .disabled
  private var _recoverResult: Result<Void, SettingsError> = .success(())
  private var _newKey: Result<String, SettingsError> = .success("EsTc abcd")
  private var _modes: [Bool: NotificationMode] = [true: .allMessages, false: .allMessages]
  private var _setModeResult: Result<Void, SettingsError> = .success(())

  public init() {}

  private var _statusMessage: String?
  /// The status message, as `setStatusMessage` leaves it.
  public var statusText: String? {
    get { lock.withLock { _statusMessage } }
    set { lock.withLock { _statusMessage = newValue } }
  }

  public func statusMessage() async -> String? { statusText }

  /// What `contactsVisibility` answers; `setContactsVisibility` changes it unless `visibilityFails`.
  public var visibility: ContactsVisibility? = .contacts
  public var visibilityFails = false

  public func contactsVisibility() async -> ContactsVisibility? { visibility }

  public func setContactsVisibility(_ visibility: ContactsVisibility) async throws(SettingsError) {
    if visibilityFails { throw .requestFailed }
    self.visibility = visibility
  }

  /// What `cacheSize` answers; clearing sets it to 0.
  public var cacheBytes: Int? = 2_048

  public func cacheSize() async -> Int? { cacheBytes }

  public func clearCache() async throws(SettingsError) { cacheBytes = 0 }

  /// What `startIdentityReset` answers; the password `finishIdentityReset` got.
  public var resetStep: IdentityResetStep = .password
  public private(set) var resetPassword: String?

  public func startIdentityReset() async throws(SettingsError) -> IdentityResetStep { resetStep }

  public func finishIdentityReset(password: String?) async throws(SettingsError) {
    resetPassword = password
  }

  public func setStatusMessage(_ message: String) async throws(SettingsError) {
    statusText = message.isEmpty ? nil : message
  }

  public var name: String? {
    get { lock.withLock { _displayName } }
    set { lock.withLock { _displayName = newValue } }
  }
  public var status: RecoveryStatus {
    get { lock.withLock { _status } }
    set { lock.withLock { _status = newValue } }
  }
  public var recoverResult: Result<Void, SettingsError> {
    get { lock.withLock { _recoverResult } }
    set { lock.withLock { _recoverResult = newValue } }
  }
  public var newKeyResult: Result<String, SettingsError> {
    get { lock.withLock { _newKey } }
    set { lock.withLock { _newKey = newValue } }
  }
  public var setModeResult: Result<Void, SettingsError> {
    get { lock.withLock { _setModeResult } }
    set { lock.withLock { _setModeResult = newValue } }
  }
  public func mode(isDirect: Bool) -> NotificationMode {
    lock.withLock { _modes[isDirect] ?? .allMessages }
  }

  private var _nameFailures = 0
  private var _nameReads = 0
  /// How many of the next profile reads fail with `.requestFailed` before one answers.
  public var nameFailures: Int {
    get { lock.withLock { _nameFailures } }
    set { lock.withLock { _nameFailures = newValue } }
  }
  /// How many times the profile was read.
  public var nameReads: Int { lock.withLock { _nameReads } }

  public func displayName() async throws(SettingsError) -> String? {
    let fails = lock.withLock {
      _nameReads += 1
      guard _nameFailures > 0 else { return false }
      _nameFailures -= 1
      return true
    }
    if fails { throw .requestFailed }
    return name
  }
  public func avatar() async -> MediaReference? { lock.withLock { _avatar } }

  private var _avatar: MediaReference?
  private var _avatarResult: Result<Void, SettingsError> = .success(())
  private var _uploads: [PictureUpload] = []

  /// What `setAvatar` and `removeAvatar` throw, if anything.
  public var avatarResult: Result<Void, SettingsError> {
    get { lock.withLock { _avatarResult } }
    set { lock.withLock { _avatarResult = newValue } }
  }
  /// The pictures set so far.
  public var uploads: [PictureUpload] { lock.withLock { _uploads } }

  public func setAvatar(_ picture: PictureUpload) async throws(SettingsError) {
    try avatarResult.get()
    lock.withLock {
      _uploads.append(picture)
      _avatar = MediaReference(source: "mxc://example.org/avatar\(_uploads.count)")
    }
  }

  public func removeAvatar() async throws(SettingsError) {
    try avatarResult.get()
    lock.withLock { _avatar = nil }
  }

  private var _blocked: [BlockedUser] = []

  /// The people the fake has blocked; unblocking removes them.
  public var blocked: [BlockedUser] {
    get { lock.withLock { _blocked } }
    set { lock.withLock { _blocked = newValue } }
  }

  public func blockedUsers() async throws(SettingsError) -> [BlockedUser] { blocked }

  public func unblock(userId: String) async throws(SettingsError) {
    lock.withLock { _blocked.removeAll { $0.id == userId } }
  }

  private var _setNameResult: Result<Void, SettingsError> = .success(())

  /// What `setDisplayName` throws, if anything; on success the fake keeps the new name.
  public var setNameResult: Result<Void, SettingsError> {
    get { lock.withLock { _setNameResult } }
    set { lock.withLock { _setNameResult = newValue } }
  }

  public func setDisplayName(_ name: String) async throws(SettingsError) {
    try setNameResult.get()
    self.name = name
  }
  public func recoveryStatus() async -> RecoveryStatus { status }

  public func recover(recoveryKey: String) async throws(SettingsError) {
    try recoverResult.get()
    status = .enabled
  }

  public func enableRecovery() async throws(SettingsError) -> String {
    let key = try newKeyResult.get()
    status = .enabled
    return key
  }

  public func defaultNotificationMode(isDirect: Bool) async -> NotificationMode {
    mode(isDirect: isDirect)
  }

  public func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)
  {
    try setModeResult.get()
    lock.withLock { _modes[isDirect] = mode }
  }
}
