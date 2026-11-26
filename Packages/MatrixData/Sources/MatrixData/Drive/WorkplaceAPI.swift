import Domain
import Foundation

struct WorkplaceAPI: Sendable {
  typealias Transport = @Sendable (URLRequest) async -> (Int, Data)?

  enum Failure: Error, Sendable, Equatable {
    case unauthorized
    case drive(DriveError)
  }

  let platform: URL
  let transport: Transport

  func exchangeToken(idToken: String) async throws(Failure) -> String {
    var request = URLRequest(url: platform.appending(path: "auth/token_exchange"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "id_token": idToken, "exchange_type": "app",
    ])
    guard let (status, data) = await transport(request) else { throw .drive(.exchangeRejected) }
    if status == 400, String(decoding: data, as: UTF8.self).lowercased().contains("not installed") {
      throw .drive(.chatAppMissing)
    }
    guard status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let token = object["access_token"] as? String, !token.isEmpty
    else { throw status == 401 ? .unauthorized : .drive(.exchangeRejected) }
    return token
  }

  func createIntent(accessToken: String, options: DrivePickerOptions) async throws(Failure)
    -> DrivePicker
  {
    var components = URLComponents(
      url: platform.appending(path: "intents"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "force_session_id", value: "true")]
    guard let url = components?.url else { throw .drive(.intentFailed) }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let config = Self.pickerConfig(options)
    request.httpBody = try? JSONSerialization.data(withJSONObject: Self.intentBody(config))
    guard let (status, data) = await transport(request) else { throw .drive(.intentFailed) }
    if status == 401 || status == 403 { throw .unauthorized }
    guard (200..<300).contains(status),
      let picker = Self.picker(from: data, acknowledgement: Self.json(config))
    else { throw .drive(.intentFailed) }
    return picker
  }

  static func pickerConfig(_ options: DrivePickerOptions) -> [String: Any] {
    var config: [String: Any] = [
      "sharingLink": ["label": options.linkLabel],
      "theme": ["type": options.isDark ? "dark" : "light"],
    ]
    if let attach = options.attachLabel {
      var download: [String: Any] = ["label": attach, "allowFolder": false]
      if let max = options.maxAttachmentBytes { download["maxFileSize"] = max }
      config["downloadLink"] = download
    }
    return config
  }

  static func intentBody(_ config: [String: Any]) -> [String: Any] {
    [
      "data": [
        "type": "io.cozy.intents",
        "attributes": [
          "action": "PICK", "type": "io.cozy.files", "permissions": ["GET"], "data": config,
        ],
      ]
    ]
  }

  static func picker(from data: Data, acknowledgement: String) -> DrivePicker? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let body = object["data"] as? [String: Any], let id = body["id"] as? String,
      let attributes = body["attributes"] as? [String: Any],
      let services = attributes["services"] as? [[String: Any]],
      let href = services.first?["href"] as? String, let url = URL(string: href),
      url.scheme == "https",
      let client = attributes["client"] as? String,
      !client.trimmingCharacters(in: .whitespaces).isEmpty, client != "*"
    else { return nil }
    return DrivePicker(intentId: id, url: url, client: client, acknowledgement: acknowledgement)
  }

  static func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }
}
