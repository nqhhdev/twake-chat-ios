import Foundation

/// A picture, video, voice message or file the user is sending, as the Flutter composer sends it (`chat_actions.dart`
/// `PickerType`: Gallery, Documents). The file lives at `fileURL` in a folder the app owns until the upload finishes.
public struct OutgoingAttachment: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case image(width: Int?, height: Int?)
    case video(width: Int?, height: Int?, duration: TimeInterval?)
    case audio(duration: TimeInterval?)
    /// A voice message recorded in the composer, with its loudness samples (0…1) for the waveform.
    case voice(duration: TimeInterval, waveform: [Float])
    case file
  }

  public let kind: Kind
  public let fileURL: URL
  public let mimeType: String?
  public let size: Int?
  public let caption: String?
  /// The event this attachment answers, when it is a reply.
  public let replyTo: String?

  public init(
    kind: Kind, fileURL: URL, mimeType: String?, size: Int?, caption: String? = nil,
    replyTo: String? = nil
  ) {
    self.kind = kind
    self.fileURL = fileURL
    self.mimeType = mimeType
    self.size = size
    self.caption = caption
    self.replyTo = replyTo
  }
}
