import Testing

@testable import Domain

struct GeoPointTests {
  @Test func readsTheCoordinatesOfAGeoUri() {
    #expect(
      GeoPoint(geoUri: "geo:48.8566,2.3522") == GeoPoint(latitude: 48.8566, longitude: 2.3522))
    #expect(GeoPoint(geoUri: "geo:-33.9,151.2;u=35") == GeoPoint(latitude: -33.9, longitude: 151.2))
    #expect(GeoPoint(geoUri: "geo:48.85,2.35,120") == GeoPoint(latitude: 48.85, longitude: 2.35))
  }

  @Test func refusesWhatIsNotAPlace() {
    #expect(GeoPoint(geoUri: "https://example.org") == nil)
    #expect(GeoPoint(geoUri: "geo:") == nil)
    #expect(GeoPoint(geoUri: "geo:abc,2") == nil)
    #expect(GeoPoint(geoUri: "geo:91,0") == nil)
    #expect(GeoPoint(geoUri: "geo:0,181") == nil)
  }

  @Test func opensInAppleMaps() {
    let url = GeoPoint(latitude: 48.85, longitude: 2.35).appleMapsURL
    #expect(url?.absoluteString == "https://maps.apple.com/?ll=48.85,2.35&q=48.85,2.35")
  }
}
