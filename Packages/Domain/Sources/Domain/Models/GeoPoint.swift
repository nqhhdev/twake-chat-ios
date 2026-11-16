import Foundation

/// A place on the map, read from the `geo:` URI of a location message (RFC 5870: `geo:48.85,2.35;u=35`).
public struct GeoPoint: Equatable, Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  /// `nil` when the URI is not a `geo:` URI or its coordinates are not on the globe. Altitude and parameters
  /// (`;u=`) are ignored.
  public init?(geoUri: String) {
    guard geoUri.lowercased().hasPrefix("geo:") else { return nil }
    let coordinates = geoUri.dropFirst(4).split(separator: ";", maxSplits: 1).first ?? ""
    let parts = coordinates.split(separator: ",").map {
      Double($0.trimmingCharacters(in: .whitespaces))
    }
    guard parts.count >= 2, let latitude = parts[0], let longitude = parts[1],
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    else { return nil }
    self.init(latitude: latitude, longitude: longitude)
  }

  /// The link that opens this place in Apple Maps.
  public var appleMapsURL: URL? {
    var components = URLComponents(string: "https://maps.apple.com/")
    components?.queryItems = [
      URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
      URLQueryItem(name: "q", value: "\(latitude),\(longitude)"),
    ]
    return components?.url
  }
}
