import Domain
import Foundation
import MatrixRustSDK

/// `AccountSettingsRepository` on the SDK client (ADR 0006): profile, encryption recovery and notification defaults.
/// The recovery key is never logged or stored here; it is returned once to be shown to the user.
public actor AccountSettingsProxy: AccountSettingsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  /// Where a new recovery key is kept for the user's next device (ADR 0024); `nil` keeps it nowhere.
  private let recoveryVault: (any RecoveryVault)?
  /// The identity reset waiting for the user's password or web approval.
  private var pendingReset: IdentityResetHandle?
  private let capabilities: (any ServerCapabilitiesRepository)?

  public init(
    authentication: MatrixAuthenticationRepository, recoveryVault: (any RecoveryVault)? = nil,
    capabilities: (any ServerCapabilitiesRepository)? = nil
  ) {
    clientProxy = { await authentication.clientProxy }
    self.recoveryVault = recoveryVault
    self.capabilities = capabilities
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

  /// Sets recovery up and gives ToM the new key, replacing the key of an earlier setup, which opens nothing any more
  /// (ADR 0024). Settings shows the key whatever ToM answers.
  public func enableRecovery() async throws(SettingsError) -> String {
    guard let client = await clientProxy() else { throw .notSignedIn }
    let key: String
    do {
      key = try await client.client.encryption().enableRecovery(
        waitForBackupsToUpload: false, passphrase: nil, progressListener: IgnoredRecoveryProgress())
    } catch {
      throw .requestFailed
    }
    if let recoveryVault, await recoveryVault.saveRecoveryKey(key) == .alreadyKept {
      await recoveryVault.deleteRecoveryKey()
      _ = await recoveryVault.saveRecoveryKey(key)
    }
    return key
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

  public func canChangeLinkedAddresses() async -> Bool {
    guard let client = await clientProxy() else { return false }
    return (try? await client.client.homeserverCapabilities().canChangeThirdpartyIds()) ?? false
  }

  /// The pinned SDK has no 3pid calls, so these go to the client-server API with the session's token. The client
  /// secret is made here and only sent to the homeserver.
  public func sendEmailConfirmation(to email: String) async throws(SettingsError)
    -> PendingEmailLink
  {
    guard let client = await clientProxy() else { throw .notSignedIn }
    let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let secret = UUID().uuidString
    guard
      let request = ClientServerRequest.make(
        client: client.client, path: "account/3pid/email/requestToken", method: "POST",
        json: ["client_secret": secret, "email": address, "send_attempt": 1])
    else { throw .notSignedIn }
    guard let (status, data) = await ClientServerRequest.answer(request) else {
      throw .requestFailed
    }
    guard status == 200 else { throw Self.addressError(from: data) }
    guard
      let sid = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["sid"]
        as? String
    else { throw .requestFailed }
    return PendingEmailLink(email: address, clientSecret: secret, sessionId: sid)
  }

  public func linkEmail(_ pending: PendingEmailLink, auth: DeviceAuth?) async throws(SettingsError)
    -> DeviceAuthChallenge?
  {
    try await link(clientSecret: pending.clientSecret, sessionId: pending.sessionId, auth: auth)
  }

  public func sendPhoneConfirmation(to number: String, regionCode: String?)
    async throws(SettingsError) -> PendingPhoneLink
  {
    guard let client = await clientProxy() else { throw .notSignedIn }
    guard let phone = ContactAddress.phone(number, regionCode: regionCode) else {
      throw .phoneNotSupported
    }
    let secret = UUID().uuidString
    guard
      let request = ClientServerRequest.make(
        client: client.client, path: "account/3pid/msisdn/requestToken", method: "POST",
        json: Self.phoneRequestBody(phone, regionCode: regionCode, secret: secret))
    else { throw .notSignedIn }
    guard let (status, data) = await ClientServerRequest.answer(request) else {
      throw .requestFailed
    }
    guard status == 200 else { throw Self.addressError(from: data) }
    return try Self.pendingPhone(phone, secret: secret, answer: data)
  }

  public func confirmPhone(_ pending: PendingPhoneLink, code: String) async throws(SettingsError) {
    var request = URLRequest(url: pending.submitURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: Self.phoneCodeBody(pending, code: code))
    guard let (status, data) = await ClientServerRequest.answer(request) else {
      throw .requestFailed
    }
    try Self.phoneCodeAnswer(status: status, data: data)
  }

  public func linkPhone(_ pending: PendingPhoneLink, auth: DeviceAuth?) async throws(SettingsError)
    -> DeviceAuthChallenge?
  {
    try await link(clientSecret: pending.clientSecret, sessionId: pending.sessionId, auth: auth)
  }

  private func link(clientSecret: String, sessionId: String, auth: DeviceAuth?)
    async throws(SettingsError) -> DeviceAuthChallenge?
  {
    guard let client = await clientProxy() else { throw .notSignedIn }
    var payload: [String: Any] = ["client_secret": clientSecret, "sid": sessionId]
    if let auth {
      do {
        payload["auth"] = try await DevicesProxy.authBody(auth, userId: try? client.userId)
      } catch {
        throw .notSignedIn
      }
    }
    guard
      let request = ClientServerRequest.make(
        client: client.client, path: "account/3pid/add", method: "POST", json: payload)
    else { throw .notSignedIn }
    guard let (status, data) = await ClientServerRequest.answer(request) else {
      throw .requestFailed
    }
    let base = request.url?.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Self.linkAnswer(status: status, data: data, homeserver: base)
  }

  static func phoneRequestBody(_ phone: ContactAddress, regionCode: String?, secret: String)
    -> [String: Any]
  {
    [
      "client_secret": secret, "country": (regionCode ?? "").uppercased(),
      "phone_number": phone.address, "send_attempt": 1,
    ]
  }

  static func pendingPhone(_ phone: ContactAddress, secret: String, answer data: Data)
    throws(SettingsError) -> PendingPhoneLink
  {
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let sid = object?["sid"] as? String else { throw .requestFailed }
    guard let submit = object?["submit_url"] as? String, let url = URL(string: submit),
      url.scheme == "https"
    else { throw .phoneNotSupported }
    return PendingPhoneLink(
      phone: phone.address, clientSecret: secret, sessionId: sid, submitURL: url)
  }

  static func phoneCodeBody(_ pending: PendingPhoneLink, code: String) -> [String: String] {
    [
      "client_secret": pending.clientSecret, "sid": pending.sessionId,
      "token": code.trimmingCharacters(in: .whitespacesAndNewlines),
    ]
  }

  static func phoneCodeAnswer(status: Int, data: Data) throws(SettingsError) {
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    if status == 200, object?["success"] as? Bool == true { return }
    if status == 200 || (400..<500).contains(status) { throw .wrongCode }
    throw .requestFailed
  }

  public func removeLinkedAddress(_ address: LinkedAddress) async throws(SettingsError) {
    guard let client = await clientProxy(),
      let request = ClientServerRequest.make(
        client: client.client, path: "account/3pid/delete", method: "POST",
        json: Self.removalBody(address))
    else { throw .notSignedIn }
    guard await ClientServerRequest.succeeds(request) else { throw .requestFailed }
  }

  /// The answer of `/account/3pid/add`: `nil` when linked, the server's confirmation challenge (401), or the error.
  static func linkAnswer(status: Int, data: Data, homeserver base: URL?) throws(SettingsError)
    -> DeviceAuthChallenge?
  {
    if status == 200 { return nil }
    if status == 401, let challenge = DevicesProxy.challenge(from: data, homeserver: base) {
      return challenge
    }
    throw addressError(from: data)
  }

  /// The error a 3pid answer names: in use, or not confirmed yet (spec `M_THREEPID_IN_USE`, `M_THREEPID_AUTH_FAILED`).
  static func addressError(from data: Data) -> SettingsError {
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return switch object?["errcode"] as? String {
    case "M_THREEPID_IN_USE": .addressInUse
    case "M_THREEPID_AUTH_FAILED": .addressNotConfirmed
    case "M_THREEPID_MEDIUM_NOT_SUPPORTED": .phoneNotSupported
    default: .requestFailed
    }
  }

  /// The body of `/account/3pid/delete`; a phone is sent without the `+` `LinkedAddress` shows.
  static func removalBody(_ address: LinkedAddress) -> [String: String] {
    switch address.kind {
    case .email: ["medium": "email", "address": address.address]
    case .phone:
      [
        "medium": "msisdn",
        "address": address.address.hasPrefix("+")
          ? String(address.address.dropFirst()) : address.address,
      ]
    }
  }

  private func tomAccess() async -> (TwakeContactLookup, URL, String, String)? {
    guard let client = await clientProxy(), let userId = try? client.userId,
      let token = try? client.client.session().accessToken,
      let tom = await capabilities?.current().tom
    else { return nil }
    return (TwakeContactLookup(), tom.baseURL, userId, token)
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

/// The unlock after sign-in (ADR 0024) uses the same encryption calls as the Settings recovery.
extension AccountSettingsProxy: DeviceRecoveryRepository {
  public func isDeviceVerified() async -> Bool {
    guard let client = await clientProxy() else { return false }
    let encryption = client.client.encryption()
    await encryption.waitForE2eeInitializationTasks()
    return encryption.verificationState() == .verified
  }

  public func recover(recoveryKey: String, fixingBackup: Bool) async -> Bool {
    guard let client = await clientProxy() else { return false }
    let encryption = client.client.encryption()
    let key = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      if fixingBackup {
        try await encryption.recoverAndFixBackup(recoveryKey: key)
      } else {
        try await encryption.recover(recoveryKey: key)
      }
      return true
    } catch {
      DebugLog.failure(fixingBackup ? "recoverAndFixBackup" : "recover", error)
      return false
    }
  }

  /// The SDK's setup, without giving the key to ToM: the unlock decides what ToM keeps.
  public func setUpRecovery() async -> String? {
    guard let client = await clientProxy() else { return nil }
    do {
      return try await client.client.encryption().enableRecovery(
        waitForBackupsToUpload: false, passphrase: nil, progressListener: IgnoredRecoveryProgress())
    } catch {
      DebugLog.failure("setUpRecovery", error)
      return nil
    }
  }
}

private final class IgnoredRecoveryProgress: EnableRecoveryProgressListener {
  func onUpdate(status: EnableRecoveryProgress) {}
}
