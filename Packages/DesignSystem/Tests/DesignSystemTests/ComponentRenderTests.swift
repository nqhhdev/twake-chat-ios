import DesignSystem
import SwiftUI
import Testing

/// Every component renders a non-empty image in light and dark mode. No snapshot tool is chosen yet (ADR 0010),
/// so this checks that the component lays out and draws, not its pixels.
@MainActor
struct ComponentRenderTests {
  @Test(arguments: [ColorScheme.light, .dark])
  func primaryButton(scheme: ColorScheme) {
    expectRenders(Button("Sign in") {}.buttonStyle(.twakePrimary), scheme)
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func secondaryButtons(scheme: ColorScheme) {
    expectRenders(Button("Use another server") {}.buttonStyle(.twakeSecondary), scheme)
    expectRenders(Button("Cancel") {}.buttonStyle(.twakeText), scheme)
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func textField(scheme: ColorScheme) {
    expectRenders(TwakeTextField("Username", text: .constant("")), scheme)
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func listRow(scheme: ColorScheme) {
    expectRenders(TwakeListRow("Alice", subtitle: "See you tomorrow"), scheme)
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func presenceDots(scheme: ColorScheme) {
    expectRenders(AvatarPresenceDot(.online, avatarSize: 52), scheme, width: nil)
    expectRenders(AvatarPresenceDot(.away, avatarSize: 32), scheme, width: nil)
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func appBar(scheme: ColorScheme) {
    expectRenders(TwakeAppBar("Chats"), scheme)
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func logo(scheme: ColorScheme) {
    let image = expectRenders(TwakeLogo(), scheme, width: nil)
    #expect(image?.width == 225)
    #expect(image?.height == 147)
  }

  /// A missing image would leave the frame transparent: the logo's centre must be drawn.
  @Test func logoImageLoadsFromTheBundle() throws {
    let image = try #require(expectRenders(TwakeLogo(), .light, width: nil))
    var pixel: [UInt8] = [0, 0, 0, 0]
    let context = try #require(
      CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let centre = CGRect(
      x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2),
      width: CGFloat(image.width), height: CGFloat(image.height))
    context.draw(image, in: centre)
    #expect(pixel[3] > 0)
  }

  @discardableResult
  private func expectRenders(
    _ view: some View, _ scheme: ColorScheme, width: CGFloat? = 320,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> CGImage? {
    let renderer = ImageRenderer(
      content: view.frame(width: width).environment(\.colorScheme, scheme))
    renderer.scale = 1
    let image = renderer.cgImage
    #expect(image != nil, sourceLocation: sourceLocation)
    #expect((image?.width ?? 0) > 0 && (image?.height ?? 0) > 0, sourceLocation: sourceLocation)
    return image
  }
}
