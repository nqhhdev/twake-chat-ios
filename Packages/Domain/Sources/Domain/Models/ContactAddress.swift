import Foundation

public struct ContactAddress: Sendable, Equatable, Hashable, Identifiable {
  public let kind: LinkedAddress.Kind
  public let address: String

  public var id: String { "\(medium):\(address)" }

  public var medium: String {
    switch kind {
    case .email: "email"
    case .phone: "msisdn"
    }
  }

  public var matrixAddress: String {
    switch kind {
    case .email: address
    case .phone: address.hasPrefix("+") ? String(address.dropFirst()) : address
    }
  }

  private init(kind: LinkedAddress.Kind, address: String) {
    self.kind = kind
    self.address = address
  }

  public static func email(_ raw: String) -> ContactAddress? {
    let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s.]+/) != nil else { return nil }
    return ContactAddress(kind: .email, address: email)
  }

  public static func phone(_ raw: String, regionCode: String?) -> ContactAddress? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.wholeMatch(of: /\+?[0-9 ()\-.\/]+/) != nil else { return nil }
    let digits = trimmed.filter(\.isASCIIDigit)
    let international: String
    if trimmed.hasPrefix("+") {
      international = digits
    } else if digits.hasPrefix("00") {
      international = String(digits.dropFirst(2))
    } else if let code = regionCode.flatMap({ callingCodes[$0.uppercased()] }) {
      let national = digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
      international = national.hasPrefix(code) && code == "1" ? national : code + national
    } else {
      return nil
    }
    guard (8...15).contains(international.count), !international.hasPrefix("0") else { return nil }
    return ContactAddress(kind: .phone, address: "+" + international)
  }

  public static func parse(_ raw: String, regionCode: String?) -> ContactAddress? {
    email(raw) ?? phone(raw, regionCode: regionCode)
  }

  static let callingCodes: [String: String] = [
    "AT": "43", "AU": "61", "BE": "32", "BR": "55", "CA": "1", "CH": "41", "CI": "225",
    "CN": "86", "DE": "49", "DK": "45", "DZ": "213", "ES": "34", "FI": "358", "FR": "33",
    "GB": "44", "IE": "353", "IN": "91", "IT": "39", "JP": "81", "KR": "82", "LU": "352",
    "MA": "212", "NL": "31", "NO": "47", "PL": "48", "PT": "351", "RU": "7", "SE": "46",
    "SG": "65", "SN": "221", "TH": "66", "TN": "216", "US": "1", "VN": "84",
  ]
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
