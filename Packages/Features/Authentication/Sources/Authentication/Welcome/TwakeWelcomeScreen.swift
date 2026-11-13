import DesignSystem
import SwiftUI

/// linagora-design-flutter `TwakeWelcomeScreen`: the logo and description centred on the starting-page gradient, the
/// Twake ID buttons (SaaS only), the company-server link and the privacy footer. It holds no logic.
public struct TwakeWelcomeScreen: View {
  let viewModel: TwakeWelcomeViewModel
  @Environment(\.openURL) private var openURL

  public init(viewModel: TwakeWelcomeViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(spacing: 0) {
      Spacer()
      TwakeLogo(TwakeLogo.welcomeResource)
        .padding(.bottom, 32)
      Text("An open source messenger encrypt\nyour data with matrix protocol")
        .textStyle(Self.buttonText)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.black)
        .padding(.horizontal, 16)
      Spacer()
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.error)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      }
      buttons
      footer
    }
    // On a wide screen (an unfolded Duo, an iPad) the buttons keep a phone's width instead of spanning the screen.
    .frame(maxWidth: TwakeLayout.formMaxWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Self.gradient.ignoresSafeArea())
    .disabled(viewModel.isLoading)
    .overlay {
      if viewModel.isLoading { ProgressView() }
    }
  }

  private var buttons: some View {
    VStack(spacing: 12) {
      if viewModel.configuration.offersTwakeID {
        WelcomeButton(
          "Create Twake ID", background: SysColors.primary, foreground: SysColors.onPrimary
        ) { Task { await viewModel.createTwakeID() } }
        WelcomeButton("Sign in", background: SysColors.surface, foreground: SysColors.primary) {
          Task { await viewModel.signIn() }
        }
      }
      Button("Use your company server") { viewModel.useCompanyServer() }
        .textStyle(Self.buttonText)
        .underline()
        .foregroundStyle(SysColors.primary)
        .padding(16)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Text("By continuing, you're agreeing to our")
        .textStyle(TextStyleToken(size: 12, lineHeight: 16, weight: .medium, letterSpacing: 0))
        .foregroundStyle(Color(argb: SysColors.outlineVariant.dark))
      Button("Privacy Policy") { openURL(viewModel.configuration.privacyURL) }
        .textStyle(TextStyleToken(size: 14, lineHeight: 20, weight: .medium, letterSpacing: 0))
        .foregroundStyle(SysColors.primary)
    }
    .padding(.top, 16)
    .padding(.bottom, 16)
  }

  /// 17 pt medium, the welcome screen's description and button text.
  static let buttonText = TextStyleToken(
    size: 17, lineHeight: 24, weight: .medium, letterSpacing: 0)

  /// `LinagoraGradientColor.linearGradientStartingPage`.
  static let gradient = LinearGradient(
    stops: [
      .init(
        color: Color(red: 248 / 255, green: 169 / 255, blue: 52 / 255).opacity(0.2), location: 0),
      .init(
        color: Color(red: 203 / 255, green: 40 / 255, blue: 206 / 255).opacity(0.2), location: 0.436
      ),
      .init(color: Color(red: 10 / 255, green: 132 / 255, blue: 1).opacity(0.2), location: 1),
    ], startPoint: .bottomLeading, endPoint: .bottomTrailing)
}

/// `HomeserverButtonWidget`: 56 pt tall, full width, fully rounded.
private struct WelcomeButton: View {
  let title: String
  let background: ColorToken
  let foreground: ColorToken
  let action: () -> Void

  init(
    _ title: String, background: ColorToken, foreground: ColorToken, action: @escaping () -> Void
  ) {
    self.title = title
    self.background = background
    self.foreground = foreground
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .textStyle(TwakeWelcomeScreen.buttonText)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}
