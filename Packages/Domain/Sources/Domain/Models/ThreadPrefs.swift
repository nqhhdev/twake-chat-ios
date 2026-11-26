import Foundation

/// What the user chose for one thread, over what taking part in it implies (web D60).
public enum ThreadPref: String, Sendable, Equatable, CaseIterable {
  case follow
  case unfollow
  /// Followed, but silent: no unread count and no push (a push rule of its own).
  case mute
}

/// The choice for one thread, as the web client keeps it in the account data `app.twake.chat.thread_prefs`
/// (`{ "threads": [{ "roomId", "threadId", "pref" }] }`, newest first, at most 500), so both apps share it.
public struct ThreadPrefEntry: Sendable, Equatable, Hashable, Identifiable {
  public let roomId: String
  /// The event id of the thread's root.
  public let threadId: String
  public let pref: ThreadPref

  public var id: String { roomId + "|" + threadId }

  public init(roomId: String, threadId: String, pref: ThreadPref) {
    self.roomId = roomId
    self.threadId = threadId
    self.pref = pref
  }
}

/// Whether the user follows a thread, and whether it is silenced.
public struct ThreadFollow: Sendable, Equatable {
  public let isFollowing: Bool
  public let isMuted: Bool

  public init(isFollowing: Bool, isMuted: Bool) {
    self.isFollowing = isFollowing
    self.isMuted = isMuted
  }
}

public enum ThreadPrefs {
  public static let accountDataType = "app.twake.chat.thread_prefs"
  /// The id of the push rule that mutes a thread is this prefix and the thread's root event id (web
  /// `THREAD_RULE_PREFIX`).
  public static let muteRulePrefix = "app.twake.chat.thread."
  public static let maxEntries = 500

  /// The entries of the account data content; entries that are not well formed are left out, as the web reads them.
  public static func entries(fromJSON data: Data?) -> [ThreadPrefEntry] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = object["threads"] as? [Any]
    else { return [] }
    // Entry by entry, as the web filters: one malformed entry does not hide the others.
    return list.compactMap { entry in
      guard let entry = entry as? [String: Any], let roomId = entry["roomId"] as? String,
        let threadId = entry["threadId"] as? String,
        let pref = (entry["pref"] as? String).flatMap(ThreadPref.init(rawValue:))
      else { return nil }
      return ThreadPrefEntry(roomId: roomId, threadId: threadId, pref: pref)
    }
  }

  public static func json(_ entries: [ThreadPrefEntry]) -> Data? {
    try? JSONSerialization.data(withJSONObject: [
      "threads": entries.map {
        ["roomId": $0.roomId, "threadId": $0.threadId, "pref": $0.pref.rawValue]
      }
    ])
  }

  /// Sets the choice for one thread; the newest come first, at most `maxEntries` (web `withThreadPref`).
  public static func with(
    _ entries: [ThreadPrefEntry], roomId: String, threadId: String, pref: ThreadPref
  ) -> [ThreadPrefEntry] {
    let others = entries.filter { $0.roomId != roomId || $0.threadId != threadId }
    let entry = ThreadPrefEntry(roomId: roomId, threadId: threadId, pref: pref)
    return Array(([entry] + others).prefix(maxEntries))
  }

  /// The choice beats taking part; a muted thread is still followed (web `resolveThreadFollow`).
  public static func follow(isParticipating: Bool, pref: ThreadPref?) -> ThreadFollow {
    ThreadFollow(
      isFollowing: pref.map { $0 != .unfollow } ?? isParticipating, isMuted: pref == .mute)
  }

  /// The id of the push rule that mutes the thread `threadId`.
  public static func muteRuleId(threadId: String) -> String { muteRulePrefix + threadId }
}

public struct FollowedThread: Sendable, Equatable, Identifiable {
  public let entry: ThreadPrefEntry
  public let roomName: String
  public let rootSenderName: String?
  public let rootText: String?
  public let date: Date?
  public let latestSenderName: String?
  public let latestText: String?
  public let replyCount: Int
  public var id: String { entry.id }

  public init(
    entry: ThreadPrefEntry, roomName: String, rootSenderName: String?, rootText: String?,
    date: Date?, latestSenderName: String? = nil, latestText: String? = nil, replyCount: Int = 0
  ) {
    self.entry = entry
    self.roomName = roomName
    self.rootSenderName = rootSenderName
    self.rootText = rootText
    self.date = date
    self.latestSenderName = latestSenderName
    self.latestText = latestText
    self.replyCount = replyCount
  }

  public static func merged(followed: [FollowedThread], active: [FollowedThread])
    -> [FollowedThread]
  {
    let sorted = active.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    var seen = Set<String>()
    return (sorted + followed).filter { seen.insert($0.id).inserted }
  }
}

public struct ThreadActivityCandidate: Sendable, Equatable {
  public let roomId: String
  public let threadId: String
  public let rootIsOwn: Bool
  public let latestIsOwn: Bool?

  public init(roomId: String, threadId: String, rootIsOwn: Bool, latestIsOwn: Bool?) {
    self.roomId = roomId
    self.threadId = threadId
    self.rootIsOwn = rootIsOwn
    self.latestIsOwn = latestIsOwn
  }
}

extension ThreadPrefs {
  public static let subscriptionsFeature = "org.matrix.msc4306"

  public static func pref(
    of candidate: ThreadActivityCandidate, in entries: [ThreadPrefEntry]
  ) -> ThreadPref? {
    entries.first { $0.roomId == candidate.roomId && $0.threadId == candidate.threadId }?.pref
  }

  public static func isActive(_ candidate: ThreadActivityCandidate, entries: [ThreadPrefEntry])
    -> Bool
  {
    guard candidate.latestIsOwn == false else { return false }
    switch pref(of: candidate, in: entries) {
    case .follow: return true
    case .unfollow, .mute: return false
    case nil: return candidate.rootIsOwn
    }
  }

  public static func usesSubscriptions(_ unstableFeatures: Set<String>) -> Bool {
    unstableFeatures.contains(subscriptionsFeature)
  }

  public static func isSubscribed(_ pref: ThreadPref) -> Bool {
    pref == .follow
  }
}

/// The user's thread choices, shared with the web app. Implemented in MatrixData on the account data (ADR 0006).
public protocol ThreadPrefsRepository: Sendable {
  /// Every choice of the account, newest first.
  func threadPrefs() async -> [ThreadPrefEntry]
  /// Sets the choice for one thread. Mute also adds the thread's push rule, and any other choice removes it.
  func setThreadPref(_ pref: ThreadPref, roomId: String, threadId: String)
    async throws(TimelineError)
  /// The threads followed by choice (`follow` or `mute`), newest choice first, with their root's preview.
  func followedThreads() async -> [FollowedThread]
  func activeThreads(inRooms roomIds: [String]) async -> [FollowedThread]
}

extension ThreadPrefsRepository {
  public func activeThreads(inRooms roomIds: [String]) async -> [FollowedThread] { [] }
}
