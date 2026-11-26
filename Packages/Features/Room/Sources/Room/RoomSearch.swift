import DesignSystem
import Domain
import Foundation
import Observation
import SwiftUI

/// The search inside a chat (Flutter `chat_search`). A chat that is not encrypted asks the homeserver's search, a page
/// at a time, a short pause after each change of the text; the server cannot read an encrypted chat, so there the
/// device goes through the chat's text messages, loading older ones while the end of the results is on screen.
@MainActor @Observable
public final class RoomSearchViewModel {
  public enum Mode: Equatable {
    case server
    case onDevice
  }

  /// The shortest text searched on the device, as Flutter's `chatRoomSearchKeywordMin`.
  static let minimumOnDeviceLength = 2
  /// The pause after typing before the server is asked.
  static let debounce: Duration = .milliseconds(300)

  /// The search box; a change searches again.
  public var query = "" {
    didSet { if query != oldValue { queryChanged() } }
  }
  public private(set) var mode: Mode?
  /// Newest first.
  public private(set) var results: [RoomSearchResult] = []
  public private(set) var isSearching = false
  public private(set) var errorMessage: String?
  /// On the device: every message back to the start of the chat was searched.
  public private(set) var reachedStart = false

  @ObservationIgnored private let roomId: String
  @ObservationIgnored private let server: (any RoomSearchRepository)?
  @ObservationIgnored private let textTimeline: (any TimelineRepository)?
  @ObservationIgnored private let isEncrypted: @MainActor () async -> Bool
  @ObservationIgnored private var nextBatch: String?
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  /// The chat's text messages loaded so far, newest first.
  @ObservationIgnored private var messages: [TimelineMessage] = []
  @ObservationIgnored private var isOpen = false
  @ObservationIgnored private var indexHits: [RoomSearchResult] = []
  @ObservationIgnored private var isLoadingOlder = false

  public init(
    roomId: String, server: (any RoomSearchRepository)?, textTimeline: (any TimelineRepository)?,
    isEncrypted: @escaping @MainActor () async -> Bool
  ) {
    self.roomId = roomId
    self.server = server
    self.textTimeline = textTimeline
    self.isEncrypted = isEncrypted
  }

  /// Picks the way to search; on the device, opens the text messages and follows them until the calling task ends.
  public func start() async {
    if server != nil, await !isEncrypted() {
      mode = .server
      return
    }
    guard let textTimeline else {
      mode = server == nil ? nil : .server
      return
    }
    mode = .onDevice
    let items: AsyncStream<[TimelineItem]>
    do {
      items = try await textTimeline.open()
    } catch {
      errorMessage = "Could not search this chat."
      return
    }
    isOpen = true
    for await list in items {
      messages = list.reversed().compactMap { item in
        if case .message(let message) = item.kind { message } else { nil }
      }
      if list.contains(where: { $0.kind == .timelineStart }) { reachedStart = true }
      filterOnDevice()
    }
    isOpen = false
    await textTimeline.close()
  }

  /// Whether more results may come: another server page, or older messages to go through on the device.
  public var hasMore: Bool {
    switch mode {
    case .server: nextBatch != nil
    case .onDevice: !reachedStart && Self.trimmed(query).count >= Self.minimumOnDeviceLength
    case nil: false
    }
  }

  /// The next server page, when the last result shows.
  public func loadMore() async {
    guard mode == .server, let server, let from = nextBatch, !isSearching else { return }
    let term = Self.serverTerm(query)
    isSearching = true
    defer { isSearching = false }
    do {
      let page = try await server.search(term, roomId: roomId, from: from)
      guard term == Self.serverTerm(query) else { return }
      results += page.results
      nextBatch = page.nextBatch
    } catch {
      errorMessage = "Could not search. Please try again."
    }
  }

  /// On the device, loads older messages while the calling task runs (the end of the results is on screen).
  public func loadOlderWhileVisible() async {
    while mode == .onDevice, hasMore, !Task.isCancelled {
      var loaded = true
      if isOpen, !isLoadingOlder, let textTimeline {
        isLoadingOlder = true
        do {
          if try await textTimeline.loadOlder() { reachedStart = true }
        } catch {
          loaded = false
        }
        isLoadingOlder = false
      }
      try? await Task.sleep(for: loaded ? .milliseconds(250) : .seconds(3))
    }
  }

  private func queryChanged() {
    searchTask?.cancel()
    switch mode {
    case .onDevice:
      filterOnDevice()
      searchTask = Task { [weak self] in
        try? await Task.sleep(for: Self.debounce)
        guard !Task.isCancelled else { return }
        await self?.searchIndex()
      }
    case .server:
      // Searching from the first key: the pause before asking must not read as "no results".
      isSearching = !Self.serverTerm(query).isEmpty
      searchTask = Task { [weak self] in
        try? await Task.sleep(for: Self.debounce)
        guard !Task.isCancelled else { return }
        await self?.searchServer()
      }
    case nil:
      break
    }
  }

  private func searchServer() async {
    let term = Self.serverTerm(query)
    nextBatch = nil
    errorMessage = nil
    guard !term.isEmpty, let server else {
      results = []
      return
    }
    isSearching = true
    defer { isSearching = false }
    do {
      let page = try await server.search(term, roomId: roomId, from: nil)
      guard term == Self.serverTerm(query) else { return }
      results = page.results
      nextBatch = page.nextBatch
    } catch {
      results = []
      errorMessage = "Could not search. Please try again."
    }
  }

  func searchIndex() async {
    let term = Self.trimmed(query)
    guard term.count >= Self.minimumOnDeviceLength, let server else {
      indexHits = []
      return
    }
    let hits = await server.searchOnDevice(term, roomId: roomId)
    guard term == Self.trimmed(query), mode == .onDevice else { return }
    indexHits = hits
    filterOnDevice()
  }

  private func filterOnDevice() {
    let words = Self.words(in: query)
    guard Self.trimmed(query).count >= Self.minimumOnDeviceLength, !words.isEmpty else {
      results = []
      return
    }
    let loaded = messages.compactMap { message -> RoomSearchResult? in
      guard let eventId = message.eventId, let text = RoomViewModel.text(of: message.body),
        Self.matches(text, words: words)
      else { return nil }
      return RoomSearchResult(
        eventId: eventId, senderId: message.senderId, senderName: message.senderName,
        date: message.date, text: text)
    }
    let shown = Set(loaded.map(\.eventId))
    let indexed = indexHits.filter {
      !shown.contains($0.eventId) && Self.matches($0.text, words: words)
    }.map {
      RoomSearchResult(
        eventId: $0.eventId, senderId: $0.senderId, senderName: $0.senderName, date: $0.date,
        text: $0.text)
    }
    results = indexed.isEmpty ? loaded : (loaded + indexed).sorted { $0.date > $1.date }
  }

  static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The words of a search, each to be found in a message.
  static func words(in query: String) -> [String] {
    trimmed(query).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  /// Whether every word is in the text, ignoring case and accents.
  static func matches(_ text: String, words: [String]) -> Bool {
    words.allSatisfy {
      text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  /// The term the server gets: without "scheme://" parts, which its full-text search does not match (Flutter
  /// `removeUrlSeparatorAndPreceding`).
  static func serverTerm(_ query: String) -> String {
    let withoutSchemes = query.replacing(#/[^ ]{0,100}:\/\//#, with: "")
    return trimmed(withoutSchemes.replacing(#/ {0,10}:\/\/ {0,10}/#, with: " "))
  }
}

/// One search is one value: the room pushes it with `navigationDestination(item:)`.
extension RoomSearchViewModel: Hashable {
  nonisolated public static func == (lhs: RoomSearchViewModel, rhs: RoomSearchViewModel) -> Bool {
    lhs === rhs
  }
  nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// The search screen: the system search field, focused, and the results with the words found highlighted. A result
/// goes back to the chat on that message: the room closes this page in `onPick` (while the search field is active,
/// `dismiss` would only close the field).
struct RoomSearchScreen: View {
  @Bindable var viewModel: RoomSearchViewModel
  let onPick: (String) -> Void
  @State private var isFieldPresented = true

  var body: some View {
    List {
      ForEach(viewModel.results) { result in
        Button {
          onPick(result.eventId)
        } label: {
          ResultRow(result: result, words: RoomSearchViewModel.words(in: viewModel.query))
        }
        .foregroundStyle(SysColors.onSurface)
        .onAppear {
          if result.id == viewModel.results.last?.id { Task { await viewModel.loadMore() } }
        }
      }
      if viewModel.mode == .onDevice, viewModel.hasMore {
        HStack(spacing: 8) {
          ProgressView()
          Text("Searching older messages…").font(.footnote).foregroundStyle(
            SysColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .task(id: viewModel.query) { await viewModel.loadOlderWhileVisible() }
      }
      if let message = viewModel.errorMessage {
        Text(message).foregroundStyle(SysColors.error)
      }
    }
    .overlay { emptyState }
    .searchable(
      text: $viewModel.query, isPresented: $isFieldPresented,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search messages"
    )
    .navigationTitle("Search")
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.start() }
  }

  @ViewBuilder private var emptyState: some View {
    let query = RoomSearchViewModel.trimmed(viewModel.query)
    if query.isEmpty {
      ContentUnavailableView {
        Label("Search this chat", systemImage: "magnifyingglass")
      } description: {
        if viewModel.mode == .onDevice {
          Text("This chat is encrypted, so its messages are searched on this device.")
        }
      }
    } else if viewModel.results.isEmpty, viewModel.isSearching {
      ProgressView()
    } else if viewModel.results.isEmpty, !viewModel.hasMore, viewModel.errorMessage == nil {
      ContentUnavailableView.search(text: query)
    }
  }
}

/// A result: the sender and date, then the message with the words found in bold and the accent colour.
private struct ResultRow: View {
  let result: RoomSearchResult
  let words: [String]
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(result.senderName).font(.subheadline.weight(.semibold)).lineLimit(1)
        Spacer()
        Text(result.date.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(SysColors.textSecondary)
      }
      Text(highlighted).font(.subheadline).lineLimit(3)
    }
    .padding(.vertical, 2)
  }

  private var highlighted: AttributedString {
    var text = AttributedString(result.text)
    for word in words where !word.isEmpty {
      var searchRange = text.startIndex..<text.endIndex
      while let found = text[searchRange].range(
        of: word, options: [.caseInsensitive, .diacriticInsensitive])
      {
        text[found].foregroundColor = SysColors.primary.color(for: colorScheme)
        text[found].inlinePresentationIntent = .stronglyEmphasized
        searchRange = found.upperBound..<text.endIndex
      }
    }
    return text
  }
}
