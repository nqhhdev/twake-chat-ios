import SwiftUI

enum Localization {
  static let bundle = Bundle.module
}

func localized(_ key: String.LocalizationValue) -> String {
  String(localized: key, bundle: Localization.bundle)
}
