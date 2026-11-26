import Domain
import Foundation
import SQLite3

public actor MessageIndex {
  struct Location: Sendable, Equatable {
    let userId: String
    let url: URL
  }

  struct Entry: Sendable, Equatable {
    let eventId: String
    let roomId: String
    let senderId: String
    let senderName: String
    let date: Date
    let text: String
  }

  static let searchLimit = 50

  private let location: @Sendable () async -> Location?
  private var database: OpaquePointer?
  private var openedAt: Location?

  public init(authentication: MatrixAuthenticationRepository) {
    location = {
      guard let client = await authentication.clientProxy, let userId = try? client.userId else {
        return nil
      }
      return Location(userId: userId, url: authentication.messageIndexURL)
    }
  }

  init(location: @escaping @Sendable () async -> Location?) {
    self.location = location
  }

  func record(_ entries: [Entry]) async {
    guard !entries.isEmpty, let database = await open() else { return }
    let sql = """
      INSERT INTO message(event_id, room_id, sender_id, sender_name, ts, body)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(event_id) DO UPDATE SET body = excluded.body, sender_name = excluded.sender_name
      """
    Self.execute("BEGIN", on: database)
    for entry in entries {
      Self.run(
        sql,
        [
          .text(entry.eventId), .text(entry.roomId), .text(entry.senderId), .text(entry.senderName),
          .real(entry.date.timeIntervalSince1970), .text(entry.text),
        ], on: database)
    }
    Self.execute("COMMIT", on: database)
  }

  func remove(eventIds: [String]) async {
    guard !eventIds.isEmpty, let database = await open() else { return }
    Self.execute("BEGIN", on: database)
    for eventId in eventIds {
      Self.run("DELETE FROM message WHERE event_id = ?", [.text(eventId)], on: database)
    }
    Self.execute("COMMIT", on: database)
  }

  func search(_ term: String, roomId: String?, limit: Int = searchLimit) async
    -> [RoomSearchResult]
  {
    guard let match = Self.matchQuery(term), let database = await open() else { return [] }
    var sql = """
      SELECT m.event_id, m.room_id, m.sender_id, m.sender_name, m.ts, m.body
      FROM message_fts JOIN message m ON m.rowid = message_fts.rowid
      WHERE message_fts MATCH ?
      """
    var values: [Value] = [.text(match)]
    if let roomId {
      sql += " AND m.room_id = ?"
      values.append(.text(roomId))
    }
    sql += " ORDER BY m.ts DESC LIMIT ?"
    values.append(.integer(limit))
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    Self.bind(values, to: statement)
    var results: [RoomSearchResult] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(
        RoomSearchResult(
          eventId: Self.column(statement, 0), senderId: Self.column(statement, 2),
          senderName: Self.column(statement, 3),
          date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
          text: Self.column(statement, 5), roomId: Self.column(statement, 1)))
    }
    return results
  }

  func close() {
    if let database { sqlite3_close_v2(database) }
    database = nil
    openedAt = nil
  }

  static func matchQuery(_ term: String) -> String? {
    let words = term.split(whereSeparator: { $0.isWhitespace || $0 == "\"" })
      .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
    return words.isEmpty ? nil : words.joined(separator: " ")
  }

  static func entries(roomId: String, items: [TimelineItem]) -> (
    entries: [Entry], redacted: [String]
  ) {
    var entries: [Entry] = []
    var redacted: [String] = []
    for item in items {
      guard case .message(let message) = item.kind, let eventId = message.eventId else { continue }
      if message.body == .redacted {
        redacted.append(eventId)
        continue
      }
      guard message.sendState == .sent, let text = message.body.plainText,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { continue }
      entries.append(
        Entry(
          eventId: eventId, roomId: roomId, senderId: message.senderId,
          senderName: message.senderName, date: message.date, text: text))
    }
    return (entries, redacted)
  }

  private func open() async -> OpaquePointer? {
    guard let current = await location() else {
      close()
      return nil
    }
    let path = current.url.path(percentEncoded: false)
    if let database, openedAt == current, FileManager.default.fileExists(atPath: path) {
      return database
    }
    close()
    guard
      FileManager.default.fileExists(
        atPath: current.url.deletingLastPathComponent().path(percentEncoded: false))
    else { return nil }
    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
      sqlite3_close_v2(opened)
      return nil
    }
    for statement in Self.schema { Self.execute(statement, on: opened) }
    database = opened
    openedAt = current
    return opened
  }

  static let schema = [
    """
    CREATE TABLE IF NOT EXISTS message(
      rowid INTEGER PRIMARY KEY, event_id TEXT NOT NULL UNIQUE, room_id TEXT NOT NULL,
      sender_id TEXT NOT NULL, sender_name TEXT NOT NULL, ts REAL NOT NULL, body TEXT NOT NULL)
    """,
    "CREATE INDEX IF NOT EXISTS message_room ON message(room_id, ts)",
    """
    CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
      body, content = 'message', content_rowid = 'rowid', tokenize = 'unicode61 remove_diacritics 2')
    """,
    """
    CREATE TRIGGER IF NOT EXISTS message_ai AFTER INSERT ON message BEGIN
      INSERT INTO message_fts(rowid, body) VALUES (new.rowid, new.body);
    END
    """,
    """
    CREATE TRIGGER IF NOT EXISTS message_ad AFTER DELETE ON message BEGIN
      INSERT INTO message_fts(message_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
    END
    """,
    """
    CREATE TRIGGER IF NOT EXISTS message_au AFTER UPDATE ON message BEGIN
      INSERT INTO message_fts(message_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
      INSERT INTO message_fts(rowid, body) VALUES (new.rowid, new.body);
    END
    """,
  ]

  enum Value {
    case text(String)
    case real(Double)
    case integer(Int)
  }

  private static func execute(_ sql: String, on database: OpaquePointer) {
    sqlite3_exec(database, sql, nil, nil, nil)
  }

  private static func run(_ sql: String, _ values: [Value], on database: OpaquePointer) {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(statement) }
    bind(values, to: statement)
    sqlite3_step(statement)
  }

  private static func bind(_ values: [Value], to statement: OpaquePointer?) {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      switch value {
      case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
      case .real(let number): sqlite3_bind_double(statement, index, number)
      case .integer(let number): sqlite3_bind_int64(statement, index, Int64(number))
      }
    }
  }

  private static func column(_ statement: OpaquePointer?, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
  }
}
