import Foundation
import Testing

@testable import MatrixData

struct AttachmentCryptoTests {
  private let key = Data((0..<32).map { UInt8($0) })
  private let iv = Data([1, 2, 3, 4, 5, 6, 7, 8]) + Data(count: 8)

  @Test func aesCtrMatchesOpenSsl() throws {
    let sealed = try AttachmentCrypto.encrypt(Data("Hello, Matrix album!".utf8), key: key, iv: iv)
    #expect(sealed.data.base64EncodedString() == "LQcXvUjYdSzujaKZ+f9M2IbULp0=")
  }

  @Test func decryptingWithTheSameKeyGivesTheFileBack() throws {
    let plain = Data((0..<5000).map { UInt8($0 % 251) })
    let sealed = try AttachmentCrypto.encrypt(plain)
    #expect(sealed.data != plain)
    #expect(sealed.iv.suffix(8) == Data(count: 8))
    #expect(try AttachmentCrypto.ctr(sealed.data, key: sealed.key, iv: sealed.iv) == plain)
  }

  @Test func theFileObjectFollowsTheMatrixAttachmentFormat() throws {
    let sealed = try AttachmentCrypto.encrypt(Data("Hello, Matrix album!".utf8), key: key, iv: iv)
    let file = sealed.file(url: "mxc://example.org/abc")
    #expect(file["url"] as? String == "mxc://example.org/abc")
    #expect(file["v"] as? String == "v2")
    #expect(file["iv"] as? String == "AQIDBAUGBwgAAAAAAAAAAA")
    #expect(
      (file["hashes"] as? [String: String])?["sha256"]
        == "IoWbLPu+NeJyMS9cgfCFTEMjiCMvN0el0/B4dMessDM")
    let jwk = try #require(file["key"] as? [String: Any])
    #expect(jwk["alg"] as? String == "A256CTR")
    #expect(jwk["kty"] as? String == "oct")
    #expect(jwk["ext"] as? Bool == true)
    #expect(jwk["key_ops"] as? [String] == ["encrypt", "decrypt"])
    #expect(jwk["k"] as? String == "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
  }

  @Test func aWrongKeyLengthIsRefused() {
    #expect(throws: AttachmentCrypto.Failure.self) {
      try AttachmentCrypto.ctr(Data([1]), key: Data(count: 16), iv: Data(count: 16))
    }
  }
}

struct AlbumItemContentTests {
  private func item(caption: String? = nil, isVideo: Bool = false) -> AlbumItemContent.Item {
    AlbumItemContent.Item(
      isVideo: isVideo, filename: "IMG_1.jpg", caption: caption, mimeType: "image/jpeg",
      size: 1000, width: 400, height: 300, blurhash: "LKO2", duration: isVideo ? 2.5 : nil,
      media: .url("mxc://example.org/a"), thumbnail: .file(["url": "mxc://example.org/t"]),
      thumbnailInfo: ["mimetype": "image/jpeg", "w": 80, "h": 60, "size": 10])
  }

  @Test func eachPictureCarriesTheBatchKeyAndItsMedia() {
    let content = AlbumItemContent.content(item(), batchId: "b1", replyTo: nil, threadRoot: nil)
    #expect(content["app.twake.chat.batch"] as? String == "b1")
    #expect(content["msgtype"] as? String == "m.image")
    #expect(content["body"] as? String == "IMG_1.jpg")
    #expect(content["filename"] as? String == "IMG_1.jpg")
    #expect(content["url"] as? String == "mxc://example.org/a")
    #expect(content["m.relates_to"] == nil)
    let info = content["info"] as? [String: Any]
    #expect(info?["w"] as? UInt64 == 400)
    #expect(info?["mimetype"] as? String == "image/jpeg")
    #expect(info?["xyz.amorgan.blurhash"] as? String == "LKO2")
    #expect((info?["thumbnail_file"] as? [String: Any])?["url"] as? String == "mxc://example.org/t")
  }

  @Test func theCaptionIsTheBodyAndTheReplyIsKept() {
    let content = AlbumItemContent.content(
      item(caption: " Our trip "), batchId: "b1", replyTo: "$q", threadRoot: nil)
    #expect(content["body"] as? String == "Our trip")
    #expect(content["filename"] as? String == "IMG_1.jpg")
    let relation = content["m.relates_to"] as? [String: Any]
    #expect((relation?["m.in_reply_to"] as? [String: Any])?["event_id"] as? String == "$q")
  }

  @Test func aVideoInAThreadSaysItsDurationAndThread() {
    let content = AlbumItemContent.content(
      item(isVideo: true), batchId: "b1", replyTo: nil, threadRoot: "$root")
    #expect(content["msgtype"] as? String == "m.video")
    #expect((content["info"] as? [String: Any])?["duration"] as? Int == 2500)
    let relation = content["m.relates_to"] as? [String: Any]
    #expect(relation?["rel_type"] as? String == "m.thread")
    #expect(relation?["event_id"] as? String == "$root")
    #expect(relation?["is_falling_back"] as? Bool == true)
  }
}
