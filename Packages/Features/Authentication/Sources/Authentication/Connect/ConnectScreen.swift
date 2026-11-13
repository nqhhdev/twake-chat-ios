import DesignSystem
import SwiftUI

/// The Flutter `ConnectPageView`: a back button and the homeserver's host, then the identity-provider buttons in
/// `primaryContainer`. It holds no logic.
public struct ConnectScreen: View {
  let viewModel: ConnectViewModel

  public init(viewModel: ConnectViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Text(viewModel.title)
          .textStyle(TextStyles.titleLarge)
          .lineLimit(1)
          .padding(.horizontal, 56)
        HStack {
          Button {
            viewModel.back()
          } label: {
            Image(systemName: "chevron.backward")
              .font(.system(size: 20, weight: .medium))
              .frame(width: 48, height: 48)
          }
          .accessibilityLabel("Back")
          Spacer()
        }
      }
      .foregroundStyle(SysColors.onBackground)
      .padding(.horizontal, 4)
      .frame(height: TwakeAppBar<EmptyView, EmptyView>.height)
      Spacer()
      VStack(spacing: 12) {
        ForEach(viewModel.providers) { provider in
          Button {
            Task { await viewModel.signIn(with: provider) }
          } label: {
            Label(provider.name, systemImage: "globe")
              .textStyle(TextStyles.labelLarge)
              .foregroundStyle(SysColors.onPrimaryContainer)
              .frame(maxWidth: .infinity, minHeight: 40)
              .background(SysColors.primaryContainer, in: Capsule())
          }
          .buttonStyle(.plain)
        }
        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.error)
            .multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 16)
      Spacer()
    }
    .frame(maxWidth: TwakeLayout.formMaxWidth)
    .frame(maxWidth: .infinity)
    .background(SysColors.background)
    .disabled(viewModel.isLoading)
    .overlay {
      if viewModel.isLoading { ProgressView() }
    }
  }
}
