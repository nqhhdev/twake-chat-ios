import CommonCrypto
import CryptoKit
import Foundation

enum AttachmentCrypto {
  struct Encrypted {
    let data: Data
    let key: Data
    let iv: Data

    func file(url: String) -> [String: Any] {
      [
        "url": url,
        "key": [
          "kty": "oct", "key_ops": ["encrypt", "decrypt"], "alg": "A256CTR",
          "k": AttachmentCrypto.base64URL(key), "ext": true,
        ],
        "iv": AttachmentCrypto.unpadded(iv.base64EncodedString()),
        "hashes": [
          "sha256": AttachmentCrypto.unpadded(Data(SHA256.hash(data: data)).base64EncodedString())
        ],
        "v": "v2",
      ]
    }
  }

  enum Failure: Error {
    case cipher
  }

  static func encrypt(_ plain: Data) throws -> Encrypted {
    var key = Data(count: 32)
    var nonce = Data(count: 8)
    guard
      key.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) })
        == errSecSuccess,
      nonce.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) })
        == errSecSuccess
    else { throw Failure.cipher }
    return try encrypt(plain, key: key, iv: nonce + Data(count: 8))
  }

  static func encrypt(_ plain: Data, key: Data, iv: Data) throws -> Encrypted {
    Encrypted(data: try ctr(plain, key: key, iv: iv), key: key, iv: iv)
  }

  static func ctr(_ input: Data, key: Data, iv: Data) throws -> Data {
    guard key.count == 32, iv.count == 16 else { throw Failure.cipher }
    var cryptor: CCCryptorRef?
    let created = key.withUnsafeBytes { keyBytes in
      iv.withUnsafeBytes { ivBytes in
        CCCryptorCreateWithMode(
          CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
          CCPadding(ccNoPadding), ivBytes.baseAddress, keyBytes.baseAddress, key.count, nil, 0, 0,
          CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
      }
    }
    guard created == kCCSuccess, let cryptor else { throw Failure.cipher }
    defer { CCCryptorRelease(cryptor) }
    var output = Data(count: input.count)
    var moved = 0
    let updated = output.withUnsafeMutableBytes { outBytes in
      input.withUnsafeBytes { inBytes in
        CCCryptorUpdate(
          cryptor, inBytes.baseAddress, input.count, outBytes.baseAddress, input.count, &moved)
      }
    }
    guard updated == kCCSuccess, moved == input.count else { throw Failure.cipher }
    return output
  }

  static func unpadded(_ base64: String) -> String {
    base64.replacingOccurrences(of: "=", with: "")
  }

  static func base64URL(_ data: Data) -> String {
    unpadded(data.base64EncodedString())
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
  }
}
