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

  public func displayName() async -> String? { name }
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
