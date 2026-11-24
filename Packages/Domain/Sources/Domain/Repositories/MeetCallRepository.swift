import Foundation

/// Meet video calls of the signed-in account (#92). There is no calling in the app: a call is a Meet link, opened
/// in the browser, that the app posts in the room as the Flutter app does.
public protocol MeetCallRepository: Sendable {
  /// The account's Meet base URL, from the homeserver's well-known (`org.matrix.msc4143.rtc_foci`), already passed
  /// through `MeetLink.base`; `nil` when the server announces none, and then the app offers no calls.
  func meetBaseURL() async -> URL?

  /// Makes a new call link on `base` and posts it in the room as a text message (`text` followed by the link, the
  /// link again under `call_url`). Returns the link.
  func startCall(inRoom roomId: String, base: URL, text: String) async throws(MeetCallError) -> URL
}

public enum MeetCallError: Error, Sendable, Equatable {
  /// The user is no longer in the room; nothing was posted.
  case notJoined
  /// Meet did not make a room, or the message could not be sent.
  case failed
}
