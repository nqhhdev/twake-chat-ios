import Foundation

extension TimelineMessage.Body {
  public var plainText: String? {
    switch self {
    case .text(let text), .emote(let text), .notice(let text), .location(let text, _): text
    case .image(let caption), .video(let caption), .audio(let caption): caption
    case .file(let name): name
    case .poll(let question): question
    case .sticker, .redacted, .unableToDecrypt, .unsupported: nil
    }
  }
}
