import Domain
import Foundation
import Testing

@testable import MatrixData

/// A failed send names its cause, so the room can say why, instead of one "request failed" for every SDK error. The
/// SDK errors are written as implicit enum members of the mapper's parameter types, so this file does not import the
/// SDK (ADR 0006, scripts/check-architecture.sh rule 1).
struct TimelineErrorMapperTests {
  @Test func theServerErrorKindsOfTheIssueKeepTheirMeaning() {
    #expect(
      TimelineErrorMapper.map(
        client: .MatrixApi(kind: .tooLarge, code: "M_TOO_LARGE", msg: "", details: nil))
        == .tooLarge)
    #expect(
      TimelineErrorMapper.map(
        client: .MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "", details: nil))
        == .forbidden)
    #expect(
      TimelineErrorMapper.map(
        client: .MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)) == .network)
    #expect(
      TimelineErrorMapper.map(
        client: .MatrixApi(kind: .connectionTimeout, code: "", msg: "", details: nil)) == .network)
  }

  @Test func otherServerErrorsAndGenericOnesMayBeTriedAgain() {
    #expect(
      TimelineErrorMapper.map(
        client: .MatrixApi(kind: .unknown, code: "M_UNKNOWN", msg: "", details: nil))
        == .requestFailed)
    #expect(
      TimelineErrorMapper.map(
        client: .MatrixApi(kind: .notFound, code: "M_NOT_FOUND", msg: "", details: nil))
        == .requestFailed)
    #expect(TimelineErrorMapper.map(client: .Generic(msg: "x", details: nil)) == .requestFailed)
  }

  @Test func attachmentErrorsNameTheFileProblem() {
    #expect(
      TimelineErrorMapper.map(room: .InvalidAttachmentMimeType(message: "x")) == .unsupportedType)
    #expect(TimelineErrorMapper.map(room: .FailedSendingAttachment(message: "x")) == .uploadFailed)
    #expect(TimelineErrorMapper.map(room: .InvalidAttachmentData(message: "x")) == .uploadFailed)
    #expect(TimelineErrorMapper.map(room: .InvalidMediaInfo(message: "x")) == .uploadFailed)
    #expect(TimelineErrorMapper.map(room: .InvalidThumbnailData(message: "x")) == .uploadFailed)
    #expect(TimelineErrorMapper.map(room: .TimelineUnavailable(message: "x")) == .unavailable)
    #expect(TimelineErrorMapper.map(room: .InvalidRepliedToEventId(message: "x")) == .requestFailed)
  }

  @Test func aDomainErrorThrownInsideTheProxyIsKept() {
    #expect(TimelineErrorMapper.map(TimelineError.roomNotFound) == .roomNotFound)
  }

  @Test func anyOtherErrorMayBeTriedAgain() {
    #expect(TimelineErrorMapper.map(CocoaError(.fileReadUnknown)) == .requestFailed)
  }
}
