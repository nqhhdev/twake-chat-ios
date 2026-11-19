import Domain
import Foundation
import MatrixRustSDK

/// Maps the errors the SDK throws from a timeline or room call to the Domain's `TimelineError`, by case and never by
/// message text (ADR 0006). Sending an attachment throws `RoomError`; most other timeline calls throw `ClientError`.
enum TimelineErrorMapper {
  static func map(_ error: any Error) -> TimelineError {
    switch error {
    case let error as TimelineError: error
    case let error as ClientError: map(client: error)
    case let error as RoomError: map(room: error)
    default: .requestFailed
    }
  }

  static func map(client error: ClientError) -> TimelineError {
    guard case .MatrixApi(let kind, _, _, _) = error else { return .requestFailed }
    return switch kind {
    case .tooLarge: .tooLarge
    case .forbidden: .forbidden
    case .connectionFailed, .connectionTimeout: .network
    default: .requestFailed
    }
  }

  static func map(room error: RoomError) -> TimelineError {
    switch error {
    case .InvalidAttachmentMimeType: .unsupportedType
    case .InvalidAttachmentData, .InvalidMediaInfo, .InvalidThumbnailData,
      .FailedSendingAttachment:
      .uploadFailed
    case .TimelineUnavailable: .unavailable
    case .InvalidRepliedToEventId: .requestFailed
    }
  }
}
