import Domain
import Foundation
import MatrixRustSDK

/// `AccountSettingsRepository` on the SDK client (ADR 0006): profile, encryption recovery and notification defaults.
/// The recovery key is never logged or stored here; it is returned once to be shown to the user.
public actor AccountSettingsProxy: AccountSettingsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  /// The identity reset waiting for the user's password or web approval.
  private var pendingReset: IdentityResetHandle?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  /// `GET /profile/{userId}`, as Flutter `fetchOwnProfile` reads it: an unset name is `nil`, a failed request throws.
  public func displayName() async throws(SettingsError) -> String? {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      let profile = try await client.client.getProfile(userId: client.userId)
      return profile.displayName.flatMap { $0.isEmpty ? nil : $0 }
    } catch {
      DebugLog.failure("ownDisplayName", error)
      throw .requestFailed
    }
  }

  public func avatar() async -> MediaReference? {
    guard let client = await clientProxy() else { return nil }
    return RoomSummaryMapper.avatar((try? await client.client.avatarUrl()) ?? nil)
  }

  public func blockedUsers() async throws(SettingsError) -> [BlockedUser] {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    let ids: [String]
    do { ids = try await client.ignoredUsers() } catch { throw .requestFailed }
    var users: [BlockedUser] = []
    for id in ids {
      let name = (try? await client.getProfile(userId: id))?.displayName
      users.append(BlockedUser(id: id, displayName: name))
    }
    return users.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func unblock(userId: String) async throws(SettingsError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do { try await client.unignoreUser(userId: userId) } catch { throw .requestFailed }
  }

  public func setDisplayName(_ name: String) async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do { try await client.client.setDisplayName(name: name) } catch { throw .requestFailed }
  }

  public func setAvatar(_ picture: PictureUpload) async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      try await client.client.uploadAvatar(mimeType: picture.mimeType, data: picture.data)
    } catch {
      throw .requestFailed
    }
  }

  public func removeAvatar() async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do { try await client.client.removeAvatar() } catch { throw .requestFailed }
  }

  public func recoveryStatus() async -> RecoveryStatus {
    guard let client = await clientProxy() else { return .unknown }
    let encryption = client.client.encryption()
    await encryption.waitForE2eeInitializationTasks()
    return switch encryption.recoveryState() {
    case .enabled: .enabled
    case .disabled: .disabled
    case .incomplete: .incomplete
    default: .unknown
    }
  }

  public func recover(recoveryKey: String) async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      try await client.client.encryption().recover(
        recoveryKey: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      throw .wrongRecoveryKey
    }
  }

  public func startIdentityReset() async throws(SettingsError) -> IdentityResetStep {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      guard let handle = try await client.client.encryption().resetIdentity() else { return .done }
      pendingReset = handle
      switch handle.authType() {
      case .uiaa: return .password
      case .oidc(let info):
        guard let url = URL(string: info.approvalUrl) else { throw SettingsError.requestFailed }
        return .webApproval(url)
      }
    } catch {
      DebugLog.failure("resetIdentity", error)
      throw .requestFailed
    }
  }

  public func finishIdentityReset(password: String?) async throws(SettingsError) {
    guard let handle = pendingReset, let client = await clientProxy() else { throw .requestFailed }
    var auth: AuthData?
    if let password {
      guard let userId = try? client.userId else { throw .notSignedIn }
      auth = .password(
        passwordDetails: AuthDataPasswordDetails(identifier: userId, password: password))
    }
    do {
      try await handle.reset(auth: auth)
      pendingReset = nil
    } catch {
      DebugLog.failure("finishIdentityReset", error)
      throw .requestFailed
    }
  }

  public func cancelIdentityReset() async {
    await pendingReset?.cancel()
    pendingReset = nil
  }

  public func enableRecovery() async throws(SettingsError) -> String {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      return try await client.client.encryption().enableRecovery(
        waitForBackupsToUpload: false, passphrase: nil, progressListener: IgnoredRecoveryProgress())
    } catch {
      throw .requestFailed
    }
  }

  public func linkedAddresses() async -> [LinkedAddress] {
    guard let client = await clientProxy(),
      let request = ClientServerRequest.make(client: client.client, path: "account/3pid"),
      let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return [] }
    return LinkedAddress.addresses(fromJSON: data)
  }

  public func contactsVisibility() async -> ContactsVisibility? {
    guard let (lookup, tom, userId, token) = await tomAccess(),
      let raw = await lookup.visibility(of: userId, tom: tom, accessToken: token)
    else { return nil }
    return ContactsVisibility(rawValue: raw)
  }

  public func setContactsVisibility(_ visibility: ContactsVisibility) async throws(SettingsError) {
    guard let (lookup, tom, userId, token) = await tomAccess() else { throw .notSignedIn }
    guard
      await lookup.setVisibility(visibility.rawValue, of: userId, tom: tom, accessToken: token)
    else { throw .requestFailed }
  }

  /// The ToM server of the account, with what its calls need; `nil` without ToM.
  private func tomAccess() async -> (TwakeContactLookup, URL, String, String)? {
    let lookup = TwakeContactLookup()
    guard let client = await clientProxy(), let userId = try? client.userId,
      let token = try? client.client.session().accessToken,
      let tom = await lookup.tomServer(forUserId: userId)
    else { return nil }
    return (lookup, tom.baseURL, userId, token)
  }

  public func cacheSize() async -> Int? {
    guard let client = await clientProxy(), let sizes = try? await client.client.getStoreSizes()
    else {
      return nil
    }
    let total = [sizes.eventCacheStore, sizes.mediaStore, sizes.stateStore].compactMap { $0 }
      .reduce(0, +)
    return Int(clamping: total)
  }

  public func clearCache() async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do { try await client.clearCaches() } catch {
      DebugLog.failure("clearCaches", error)
      throw .requestFailed
    }
  }

  public func statusMessage() async -> String? {
    guard let client = await clientProxy(), let userId = try? client.userId,
      let request = ClientServerRequest.make(
        client: client.client, path: "presence/\(ClientServerRequest.encode(userId))/status"),
      let object = await ClientServerRequest.object(request)
    else { return nil }
    return (object["status_msg"] as? String).flatMap { $0.isEmpty ? nil : $0 }
  }

  public func setStatusMessage(_ message: String) async throws(SettingsError) {
    guard let client = await clientProxy(), let userId = try? client.userId else {
      throw .notSignedIn
    }
    let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let request = ClientServerRequest.make(
        client: client.client, path: "presence/\(ClientServerRequest.encode(userId))/status",
        method: "PUT", json: ["presence": "online", "status_msg": text])
    else { throw .notSignedIn }
    guard await ClientServerRequest.succeeds(request) else { throw .requestFailed }
  }

  public func isDoNotDisturbOn() async -> Bool {
    guard let request = await masterRuleRequest(method: "GET", body: nil),
      let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return object["enabled"] as? Bool ?? false
  }

  public func setDoNotDisturb(_ on: Bool) async throws(SettingsError) {
    let body = try? JSONSerialization.data(withJSONObject: ["enabled": on])
    guard let request = await masterRuleRequest(method: "PUT", body: body) else {
      throw .notSignedIn
    }
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw SettingsError.requestFailed
      }
    } catch {
      throw .requestFailed
    }
  }

  /// `/_matrix/client/v3/pushrules/global/override/.m.rule.master/enabled` with the session's access token; the
  /// pinned SDK has no call for the master rule.
  private func masterRuleRequest(method: String, body: Data?) async -> URLRequest? {
    guard let client = await clientProxy(), let session = try? client.client.session(),
      let base = URL(string: session.homeserverUrl)
    else { return nil }
    var request = URLRequest(
      url: base.appending(
        path: "_matrix/client/v3/pushrules/global/override/.m.rule.master/enabled"))
    request.httpMethod = method
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  public func defaultNotificationMode(isDirect: Bool) async -> NotificationMode {
    guard let client = await clientProxy() else { return .allMessages }
    let settings = await client.client.getNotificationSettings()
    return NotificationModeMapper.domain(
      await settings.getDefaultRoomNotificationMode(isEncrypted: false, isOneToOne: isDirect))
  }

  public func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)
  {
    guard let client = await clientProxy() else { throw .notSignedIn }
    let settings = await client.client.getNotificationSettings()
    do {
      // Encrypted and unencrypted rooms have separate rules; the user sets one mode for both.
      for isEncrypted in [false, true] {
        try await settings.setDefaultRoomNotificationMode(
          isEncrypted: isEncrypted, isOneToOne: isDirect, mode: NotificationModeMapper.sdk(mode))
      }
    } catch {
      throw .requestFailed
    }
  }
}

enum NotificationModeMapper {
  static func domain(_ mode: RoomNotificationMode) -> NotificationMode {
    switch mode {
    case .allMessages: .allMessages
    case .mentionsAndKeywordsOnly: .mentionsAndKeywords
    case .mute: .mute
    }
  }

  static func sdk(_ mode: NotificationMode) -> RoomNotificationMode {
    switch mode {
    case .allMessages: .allMessages
    case .mentionsAndKeywords: .mentionsAndKeywordsOnly
    case .mute: .mute
    }
  }
}

private final class IgnoredRecoveryProgress: EnableRecoveryProgressListener {
  func onUpdate(status: EnableRecoveryProgress) {}
}
