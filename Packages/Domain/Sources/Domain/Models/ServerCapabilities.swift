import Foundation

public struct ServerCapabilities: Sendable, Equatable {
  public struct Tom: Sendable, Equatable {
    public let baseURL: URL
    public let serverName: String

    public init(baseURL: URL, serverName: String) {
      self.baseURL = baseURL
      self.serverName = serverName
    }
  }

  public struct TwakeChat: Sendable, Equatable {
    public let supportContact: String?
    public let commonSettingsURL: String?
    public let invitationsEnabled: Bool
    public let sideService: URL?
    public let webURL: URL?
    public let driveEnabled: Bool

    public init(
      supportContact: String? = nil, commonSettingsURL: String? = nil,
      invitationsEnabled: Bool = false, sideService: URL? = nil, webURL: URL? = nil,
      driveEnabled: Bool = false
    ) {
      self.driveEnabled = driveEnabled
      self.supportContact = supportContact
      self.commonSettingsURL = commonSettingsURL
      self.invitationsEnabled = invitationsEnabled
      self.sideService = sideService
      self.webURL = webURL
    }
  }

  public let homeserver: URL?
  public let identityServer: URL?
  public let tom: Tom?
  public let callFoci: [URL]
  public let twakeChat: TwakeChat
  public let unstableFeatures: Set<String>
  public let build: BuildServices
  public let authenticationIssuer: URL?

  public init(
    homeserver: URL? = nil, identityServer: URL? = nil, tom: Tom? = nil, callFoci: [URL] = [],
    twakeChat: TwakeChat = TwakeChat(), unstableFeatures: Set<String> = [],
    build: BuildServices = BuildServices(), authenticationIssuer: URL? = nil
  ) {
    self.authenticationIssuer = authenticationIssuer
    self.homeserver = homeserver
    self.identityServer = identityServer
    self.tom = tom
    self.callFoci = callFoci
    self.twakeChat = twakeChat
    self.unstableFeatures = unstableFeatures
    self.build = build
  }

  public static let none = ServerCapabilities()

  public func supports(_ unstableFeature: String) -> Bool {
    unstableFeatures.contains(unstableFeature)
  }

  public func commonSettingsPage(for userId: String) -> URL? {
    guard let template = twakeChat.commonSettingsURL, template.contains("{username}"),
      let username = Self.localpart(of: userId)
    else { return nil }
    return URL(string: template.replacingOccurrences(of: "{username}", with: username))
  }

  public var driveSignInIssuer: URL? {
    twakeChat.driveEnabled ? authenticationIssuer : nil
  }

  public var supportContact: String? {
    twakeChat.supportContact.flatMap { $0.hasPrefix("@") && $0.contains(":") ? $0 : nil }
  }

  public var analyticsEndpoint: URL? {
    guard build.analyticsEnabled else { return nil }
    if let url = build.analyticsURL { return url }
    return twakeChat.sideService?.appending(path: "analytics/events")
  }

  static func localpart(of userId: String) -> String? {
    guard userId.hasPrefix("@"), let colon = userId.firstIndex(of: ":") else { return nil }
    let localpart = userId[userId.index(after: userId.startIndex)..<colon]
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    guard !localpart.isEmpty, localpart.unicodeScalars.allSatisfy(allowed.contains) else {
      return nil
    }
    return String(localpart)
  }
}

public struct BuildServices: Sendable, Equatable {
  public let supportURL: URL?
  public let analyticsEnabled: Bool
  public let analyticsURL: URL?
  public let apps: [TwakeApp]

  public init(
    supportURL: URL? = nil, analyticsEnabled: Bool = false, analyticsURL: URL? = nil,
    apps: [TwakeApp] = []
  ) {
    self.supportURL = supportURL
    self.analyticsEnabled = analyticsEnabled
    self.analyticsURL = analyticsURL
    self.apps = apps
  }
}

public struct TwakeApp: Sendable, Equatable, Identifiable, Decodable {
  public let id: String
  public let name: String
  public let url: URL
  public let symbol: String?

  public init(id: String, name: String, url: URL, symbol: String? = nil) {
    self.id = id
    self.name = name
    self.url = url
    self.symbol = symbol
  }
}
