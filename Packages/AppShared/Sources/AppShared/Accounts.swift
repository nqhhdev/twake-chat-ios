import Foundation

public struct AccountSlot: Codable, Sendable, Hashable {
  public static let legacy = AccountSlot(id: "legacy")
  static let accountsPathComponents = ["Library", "Application Support", "TwakeChat", "Accounts"]

  public let id: String

  public init(id: String) {
    self.id = id
  }

  public static func fresh() -> AccountSlot {
    AccountSlot(id: UUID().uuidString.lowercased())
  }

  public var isLegacy: Bool { self == .legacy }

  public var keychainAccount: String {
    isLegacy ? KeychainSessionStore.defaultAccount : "\(KeychainSessionStore.defaultAccount).\(id)"
  }

  public func storeDirectory(in containerURL: URL) -> URL {
    guard !isLegacy else { return AppGroupContainer.sdkStoreDirectory(in: containerURL) }
    return (Self.accountsPathComponents + [id, "SDK"]).reduce(containerURL) { url, component in
      url.appending(path: component, directoryHint: .isDirectory)
    }
  }
}

public struct AccountRecord: Codable, Sendable, Equatable, Identifiable {
  public let userId: String
  public let slot: AccountSlot

  public init(userId: String, slot: AccountSlot) {
    self.userId = userId
    self.slot = slot
  }

  public var id: String { userId }
}

public enum AccountChange: Sendable, Equatable {
  case added
  case alreadyAdded
  case full
}

public struct AccountList: Codable, Sendable, Equatable {
  public static let maximum = 5

  public private(set) var accounts: [AccountRecord]
  public private(set) var activeUserId: String?

  public init(accounts: [AccountRecord] = [], activeUserId: String? = nil) {
    self.accounts = accounts
    self.activeUserId =
      activeUserId.flatMap { id in
        accounts.contains { $0.userId == id } ? id : nil
      } ?? accounts.first?.userId
  }

  public var active: AccountRecord? {
    accounts.first { $0.userId == activeUserId } ?? accounts.first
  }

  public var isFull: Bool { accounts.count >= Self.maximum }

  public func account(userId: String) -> AccountRecord? {
    accounts.first { $0.userId == userId }
  }

  public func account(slot: AccountSlot) -> AccountRecord? {
    accounts.first { $0.slot == slot }
  }

  public func account(clientIdentifier: String, hash: (String) -> String) -> AccountRecord? {
    accounts.first { hash($0.userId) == clientIdentifier }
  }

  public func slotForSignIn() -> AccountSlot {
    account(slot: .legacy) == nil ? .legacy : .fresh()
  }

  public mutating func add(userId: String, slot: AccountSlot) -> AccountChange {
    if let existing = account(userId: userId) {
      if existing.slot == slot { activeUserId = userId }
      return existing.slot == slot ? .added : .alreadyAdded
    }
    guard !isFull, account(slot: slot) == nil else { return .full }
    accounts.append(AccountRecord(userId: userId, slot: slot))
    activeUserId = userId
    return .added
  }

  @discardableResult
  public mutating func remove(slot: AccountSlot) -> AccountRecord? {
    guard let index = accounts.firstIndex(where: { $0.slot == slot }) else { return nil }
    let removed = accounts.remove(at: index)
    if activeUserId == removed.userId { activeUserId = accounts.first?.userId }
    return removed
  }

  public mutating func activate(userId: String) {
    guard account(userId: userId) != nil else { return }
    activeUserId = userId
  }

  public static func migrated(_ list: AccountList?, legacyUserId: String?) -> AccountList {
    if let list, !list.accounts.isEmpty { return list }
    guard let legacyUserId, !legacyUserId.isEmpty else { return list ?? AccountList() }
    return AccountList(
      accounts: [AccountRecord(userId: legacyUserId, slot: .legacy)], activeUserId: legacyUserId)
  }
}

public struct AccountRegistry: Sendable {
  static let fileName = "accounts.json"

  public let containerURL: URL

  public init(containerURL: URL) {
    self.containerURL = containerURL
  }

  public static func inAppGroup(_ group: AppGroupContainer = AppGroupContainer())
    -> AccountRegistry?
  {
    group.containerURL().map(AccountRegistry.init(containerURL:))
  }

  public var fileURL: URL {
    AppGroupContainer.twakeChatDirectory(in: containerURL).appending(path: Self.fileName)
  }

  public func storeDirectory(for slot: AccountSlot) -> URL {
    slot.storeDirectory(in: containerURL)
  }

  public func load() -> AccountList? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(AccountList.self, from: data)
  }

  public func save(_ list: AccountList) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(list).write(to: fileURL, options: [.atomic])
  }

  public func migrate(legacyUserId: String?) -> AccountList {
    let stored = load()
    let list = AccountList.migrated(stored, legacyUserId: legacyUserId)
    if list != stored { try? save(list) }
    return list
  }

  @discardableResult
  public func update<T>(_ change: (inout AccountList) -> T) -> T {
    var list = load() ?? AccountList()
    let result = change(&list)
    try? save(list)
    return result
  }
}

extension AccountList {
  public func slot(forPush clientIdentifier: String?, hash: (String) -> String) -> AccountSlot? {
    guard !accounts.isEmpty else { return .legacy }
    guard let clientIdentifier, !clientIdentifier.isEmpty else { return active?.slot }
    return account(clientIdentifier: clientIdentifier, hash: hash)?.slot
  }

  public func notificationLabel(for slot: AccountSlot) -> String? {
    guard accounts.count > 1 else { return nil }
    return account(slot: slot)?.userId
  }
}

public struct AccountBadges {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  public static func inAppGroup() -> AccountBadges? {
    UserDefaults(suiteName: AppGroupContainer.defaultGroupIdentifier).map(AccountBadges.init)
  }

  static func key(_ slot: AccountSlot) -> String { "badge.\(slot.id)" }

  public func record(_ count: Int, for slot: AccountSlot) {
    defaults.set(max(0, count), forKey: Self.key(slot))
  }

  public func count(for slot: AccountSlot) -> Int {
    defaults.integer(forKey: Self.key(slot))
  }

  public func forget(_ slot: AccountSlot) {
    defaults.removeObject(forKey: Self.key(slot))
  }

  public func total(for list: AccountList, including slot: AccountSlot) -> Int {
    var slots = list.accounts.map(\.slot)
    if !slots.contains(slot) { slots.append(slot) }
    return slots.reduce(0) { $0 + count(for: $1) }
  }
}

public enum AccountLabel {
  public static func subtitle(_ subtitle: String, account: String?) -> String {
    guard let account, !account.isEmpty else { return subtitle }
    return subtitle.isEmpty ? account : "\(subtitle) · \(account)"
  }

  public static func accountUserId(
    senderIsMe: Bool, senderId: String?, meRecipientId: String?
  ) -> String? {
    let id = senderIsMe ? senderId : meRecipientId
    guard let id, !id.isEmpty else { return nil }
    return id
  }
}
