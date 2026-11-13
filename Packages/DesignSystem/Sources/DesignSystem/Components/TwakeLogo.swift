import SwiftUI

/// The Twake logo: twake-on-matrix `assets/logo_ios.png`, copied unchanged (see the Design System page in .okf for
/// its source). The default frame is the welcome screen's, `TwakeWelcomeViewStyle` 225 × 147; the image keeps its
/// aspect ratio inside it.
public struct TwakeLogo: View {
  /// The image set of the logo in this package's asset catalog.
  public static let resource = "logo_ios"

  private let width: CGFloat
  private let height: CGFloat

  public init(width: CGFloat = 225, height: CGFloat = 147) {
    self.width = width
    self.height = height
  }

  public var body: some View {
    Image(Self.resource, bundle: .module)
      .resizable()
      .scaledToFit()
      .frame(width: width, height: height)
      .accessibilityLabel("Twake Chat")
  }
}

#Preview("Logo, light") {
  TwakeLogo().padding().background(SysColors.background).preferredColorScheme(.light)
}

#Preview("Logo, dark") {
  TwakeLogo().padding().background(SysColors.background).preferredColorScheme(.dark)
}
