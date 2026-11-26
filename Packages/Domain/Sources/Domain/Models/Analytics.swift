import Foundation

public struct AnalyticsConsent: Sendable, Equatable {
  public static let accountDataType = "app.twake.chat.analytics_consent"

  public let granted: Bool
  public let at: Date

  public init(granted: Bool, at: Date) {
    self.granted = granted
    self.at = at
  }
}

public enum AnalyticsValue: Sendable, Equatable {
  case string(String)
  case int(Int)
  case bool(Bool)
}

public struct AnalyticsEvent: Sendable, Equatable {
  public let name: String
  public let properties: [String: AnalyticsValue]
  public let at: Date

  public init(name: String, properties: [String: AnalyticsValue] = [:], at: Date) {
    self.name = name
    self.properties = properties
    self.at = at
  }
}

public protocol AnalyticsRepository: Sendable {
  func consent() async -> AnalyticsConsent?
  func setConsent(_ consent: AnalyticsConsent) async throws(SettingsError)
  func send(_ events: [AnalyticsEvent], to endpoint: URL, appVersion: String) async -> Bool
}

public actor Analytics {
  public enum State: Sendable, Equatable {
    case unavailable
    case askConsent
    case granted
    case refused
  }

  public static let flushDelay: Duration = .seconds(5)

  private let capabilities: any ServerCapabilitiesRepository
  private let repository: any AnalyticsRepository
  private let appVersion: String
  private let now: @Sendable () -> Date
  private var consent: AnalyticsConsent??
  private var pending: [AnalyticsEvent] = []
  private var scheduledFlush: Task<Void, Never>?

  public init(
    capabilities: any ServerCapabilitiesRepository, repository: any AnalyticsRepository,
    appVersion: String, now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.capabilities = capabilities
    self.repository = repository
    self.appVersion = appVersion
    self.now = now
  }

  public func state() async -> State {
    guard await capabilities.current().analyticsEndpoint != nil else { return .unavailable }
    switch await storedConsent()?.granted {
    case true?: return .granted
    case false?: return .refused
    case nil: return .askConsent
    }
  }

  public func setConsent(_ granted: Bool) async throws(SettingsError) {
    let choice = AnalyticsConsent(granted: granted, at: now())
    try await repository.setConsent(choice)
    consent = .some(choice)
    if granted {
      track("analytics_consent_given", ["input": .string("touch")])
    } else {
      pending.removeAll()
      scheduledFlush?.cancel()
      scheduledFlush = nil
    }
  }

  public func track(_ name: String, _ properties: [String: AnalyticsValue] = [:]) {
    guard consent??.granted == true else { return }
    pending.append(AnalyticsEvent(name: name, properties: properties, at: now()))
    guard scheduledFlush == nil else { return }
    scheduledFlush = Task { [weak self] in
      try? await Task.sleep(for: Self.flushDelay)
      guard !Task.isCancelled else { return }
      await self?.flush()
    }
  }

  public func startSession() async {
    guard await state() == .granted else { return }
    track("session_started")
  }

  public func flush() async {
    scheduledFlush = nil
    guard !pending.isEmpty else { return }
    let events = pending
    pending.removeAll()
    guard await storedConsent()?.granted == true,
      let endpoint = await capabilities.current().analyticsEndpoint
    else { return }
    _ = await repository.send(events, to: endpoint, appVersion: appVersion)
  }

  private func storedConsent() async -> AnalyticsConsent? {
    if let consent { return consent }
    let stored = await repository.consent()
    consent = .some(stored)
    return stored
  }
}
