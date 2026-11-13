import SwiftUI

/// The four TwakeInter faces shipped in this package (OFL, see Resources/Fonts/LICENSE.txt).
public enum TwakeInter {
  public static let faces = [
    "TwakeInter-Regular", "TwakeInter-Medium", "TwakeInter-SemiBold", "TwakeInter-Bold",
  ]

  /// Registers the faces with the process once. `TextStyleToken.font` calls it, so callers never need to.
  public static func register() {
    _ = registration
  }

  /// The bundled file of a face, or nil when it is missing from the package resources.
  public static func url(of face: String) -> URL? {
    Bundle.module.url(forResource: face, withExtension: "ttf")
  }

  private static let registration: Void = {
    for face in faces {
      guard let url = url(of: face) else { continue }
      // Fails only when the face is already registered, which is fine.
      _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }()
}
