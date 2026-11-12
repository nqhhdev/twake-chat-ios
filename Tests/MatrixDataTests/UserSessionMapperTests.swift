import AppShared
import Domain
import Foundation
import Testing

@testable import MatrixData

/// The mapper with fixture values. The SDK values are built through the mapper itself or as implicit members of its
/// parameter types, so this file does not import the SDK (ADR 0006, scripts/check-architecture.sh rule 1).
struct UserSessionMapperTests {
  private let homeserver = URL(string: "https://matrix.example.org")!

  private func stored(refreshToken: String?, slidingSyncVersion: String?) -> StoredSession {
    StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: homeserver,
      accessToken: "access-token", refreshToken: refreshToken, slidingSyncVersion: slidingSyncVersion)
  }

  @Test(arguments: ["refresh-token", nil])
  func storedSessionRoundTripsThroughTheSDKSession(refreshToken: String?) throws {
    let record = stored(refreshToken: refreshToken, slidingSyncVersion: "native")
    let sdkSession = UserSessionMapper.sdkSession(from: record)
    #expect(try UserSessionMapper.storedSession(from: sdkSession) == record)
  }

  @Test(arguments: ["refresh-token", nil])
  func sdkSessionMapsToTheDomainSession(refreshToken: String?) throws {
    let sdkSession = UserSessionMapper.sdkSession(
      from: stored(refreshToken: refreshToken, slidingSyncVersion: "native"))
    let expected = UserSession(
      userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: homeserver,
      accessToken: "access-token", refreshToken: refreshToken)
    #expect(try UserSessionMapper.userSession(from: sdkSession) == expected)
    #expect(
      UserSessionMapper.userSession(
        from: stored(refreshToken: refreshToken, slidingSyncVersion: "native")) == expected)
  }

  @Test func slidingSyncVersionIsKept() {
    let native = UserSessionMapper.sdkSession(from: stored(refreshToken: nil, slidingSyncVersion: "native"))
    #expect(UserSessionMapper.slidingSyncName(native.slidingSyncVersion) == "native")
    let none = UserSessionMapper.sdkSession(from: stored(refreshToken: nil, slidingSyncVersion: "none"))
    #expect(UserSessionMapper.slidingSyncName(none.slidingSyncVersion) == "none")
  }

  @Test func recordWithoutSlidingSyncVersionRestoresWithNone() {
    let session = UserSessionMapper.sdkSession(from: stored(refreshToken: nil, slidingSyncVersion: nil))
    #expect(UserSessionMapper.slidingSyncName(session.slidingSyncVersion) == "none")
  }

  @Test func sessionWithoutAUsableHomeserverURLIsRejected() {
    var session = UserSessionMapper.sdkSession(from: stored(refreshToken: nil, slidingSyncVersion: "native"))
    session.homeserverUrl = "not a url"
    #expect(throws: AuthenticationError.invalidHomeserverURL) {
      try UserSessionMapper.userSession(from: session)
    }
  }

  @Test func forbiddenMeansInvalidCredentials() {
    #expect(
      UserSessionMapper.authenticationError(
        from: .MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "Invalid password", details: nil))
        == .invalidCredentials)
  }

  @Test func connectionFailuresMeanServerUnreachable() {
    #expect(
      UserSessionMapper.authenticationError(
        from: .MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)) == .serverUnreachable)
    #expect(
      UserSessionMapper.authenticationError(
        from: .MatrixApi(kind: .connectionTimeout, code: "", msg: "", details: nil)) == .serverUnreachable)
    #expect(UserSessionMapper.authenticationError(from: .ServerUnreachable(message: "")) == .serverUnreachable)
  }

  @Test func badServerNamesMeanInvalidHomeserverURL() {
    #expect(UserSessionMapper.authenticationError(from: .InvalidServerName(message: "")) == .invalidHomeserverURL)
    #expect(
      UserSessionMapper.authenticationError(from: .WellKnownLookupFailed(message: "")) == .invalidHomeserverURL)
    #expect(
      UserSessionMapper.authenticationError(from: .WellKnownDeserializationError(message: ""))
        == .invalidHomeserverURL)
  }

  @Test func otherErrorsMeanUnknown() {
    #expect(
      UserSessionMapper.authenticationError(
        from: .MatrixApi(kind: .notFound, code: "M_NOT_FOUND", msg: "", details: nil)) == .unknown)
    #expect(UserSessionMapper.authenticationError(from: .Generic(msg: "", details: nil)) == .unknown)
    #expect(UserSessionMapper.authenticationError(from: .SlidingSyncVersion(message: "")) == .unknown)
    #expect(UserSessionMapper.authenticationError(from: KeychainSessionStoreError(status: -1)) == .unknown)
  }

  @Test func anAuthenticationErrorIsKept() {
    let error: any Error = AuthenticationError.invalidHomeserverURL
    #expect(UserSessionMapper.authenticationError(from: error) == .invalidHomeserverURL)
  }
}
