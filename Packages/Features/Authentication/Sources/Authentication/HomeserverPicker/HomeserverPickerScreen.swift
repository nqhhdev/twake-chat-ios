import DesignSystem
import SwiftUI

/// The Flutter `HomeserverPickerView` on mobile: a back button, "Select your server", an outlined homeserver field,
/// the wrong-server explanation, and Continue. It holds no logic.
public struct HomeserverPickerScreen: View {
  @Bindable var viewModel: HomeserverPickerViewModel
  @FocusState private var isFieldFocused: Bool

  public init(viewModel: HomeserverPickerViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          viewModel.back()
        } label: {
          Image(systemName: "chevron.backward")
            .font(.system(size: 20, weight: .medium))
            .frame(width: 48, height: 48)
        }
        .accessibilityLabel("Back")
        .foregroundStyle(SysColors.onBackground)
        Spacer()
      }
      .padding(.horizontal, 4)
      Spacer()
      Text("Select your server")
        .textStyle(TextStyles.headlineMedium)
        .foregroundStyle(SysColors.onBackground)
        .padding(.bottom, 48)
      field
        .padding(.horizontal, 16)
      if viewModel.isWrongServerName {
        Text("Server address was sent to you by company admin. Check the invitation email.")
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.outline)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.top, 4)
      }
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.error)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.top, 4)
      }
      Button {
        Task { await viewModel.continueTapped() }
      } label: {
        Group {
          if viewModel.isLoading {
            ProgressView().tint(SysColors.onPrimary.color(for: .light))
          } else {
            Text("Continue").textStyle(TextStyles.labelLarge)
          }
        }
        // The style pads by 16 on each side: 24 here makes the button 56 high, as the welcome screen's buttons.
        .frame(maxWidth: .infinity, minHeight: 24)
      }
      .buttonStyle(.twakePrimary)
      .padding(16)
      Spacer()
    }
    .frame(maxWidth: TwakeLayout.formMaxWidth)
    .frame(maxWidth: .infinity)
    .background(SysColors.background)
    .disabled(viewModel.isLoading)
    .onAppear { isFieldFocused = true }
  }

  private var field: some View {
    let isWrong = viewModel.isWrongServerName
    return VStack(alignment: .leading, spacing: 4) {
      Text(isWrong ? "Wrong server name" : "Homeserver")
        .textStyle(TextStyles.bodySmall)
        .foregroundStyle(isWrong ? SysColors.error : SysColors.onSurface)
      TextField("Enter your homeserver", text: $viewModel.server)
        .textStyle(TextStyles.bodyLarge)
        .textContentType(.URL)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.continue)
        .focused($isFieldFocused)
        .onSubmit { Task { await viewModel.continueTapped() } }
        .padding(16)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .strokeBorder(isWrong ? SysColors.error : SysColors.outline, lineWidth: isWrong ? 2 : 1)
        )
    }
  }
}
