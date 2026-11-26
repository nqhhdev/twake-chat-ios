import DesignSystem
import Domain
import SwiftUI
import UIKit

struct PersonalQRScreen: View {
  let settings: SettingsViewModel
  @State private var isScanning = false
  @State private var shareImage: Image?

  private var viewModel: PersonalQRViewModel { settings.personalQR }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        ZStack(alignment: .top) {
          PersonalQRCard(userId: viewModel.userId, link: viewModel.link)
            .padding(.top, 36)
          TwakeAvatar(
            name: settings.displayName, size: 72, pictureID: settings.avatar?.source,
            load: settings.avatar.map { reference in
              { @Sendable [settings] in await settings.picture(reference) }
            }
          )
          .overlay(Circle().stroke(Color.white, lineWidth: 3))
        }
        HStack(spacing: 12) {
          if let shareImage, let link = viewModel.link {
            ShareLink(
              item: shareImage, message: Text(link.absoluteString),
              preview: SharePreview(localized("Your personal QR"), image: shareImage)
            ) {
              actionLabel("Share QR code", systemImage: "square.and.arrow.up")
            }
          }
          Button {
            viewModel.copyLink()
          } label: {
            actionLabel(
              viewModel.didCopyLink ? localized("Copied") : localized("Copy link"),
              systemImage: viewModel.didCopyLink ? "checkmark" : "link")
          }
        }
        .buttonStyle(.plain)
      }
      .padding(24)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .background(SysColors.surface)
    .navigationTitle(localized("Your personal QR"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewModel.canScan {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isScanning = true
          } label: {
            Label(localized("Scan QR code"), systemImage: "qrcode.viewfinder")
          }
        }
      }
    }
    .sheet(isPresented: $isScanning, onDismiss: viewModel.scannerClosed) {
      QRScannerSheet(error: viewModel.scanError) { code in
        if viewModel.scanned(code) { isScanning = false }
      }
    }
    .task(id: viewModel.didCopyLink) {
      guard viewModel.didCopyLink else { return }
      try? await Task.sleep(for: .seconds(2))
      viewModel.linkCopyShown()
    }
    .onAppear { renderShareImage() }
  }

  private func actionLabel(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .textStyle(TextStyles.labelLarge)
      .foregroundStyle(SysColors.primary)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(SysColors.onPrimary)
      .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func renderShareImage() {
    guard shareImage == nil else { return }
    let renderer = ImageRenderer(
      content: PersonalQRCard(userId: viewModel.userId, link: viewModel.link)
        .frame(width: 360)
        .padding(24)
        .background(Color.white)
        .environment(\.colorScheme, .light))
    renderer.scale = 3
    if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
  }
}

struct PersonalQRCard: View {
  let userId: String
  let link: URL?

  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        if let link, let image = QRCodeImage.make(from: link.absoluteString) {
          Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .accessibilityLabel(localized("QR code of \(userId)"))
          TwakeLogo(width: 52, height: 52)
            .padding(6)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
        }
      }
      .frame(width: 220, height: 220)
      Text(userId)
        .textStyle(TextStyles.titleMedium)
        .foregroundStyle(Color.black)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .textSelection(.enabled)
      Text(localized("Scan this code to start a chat with me."))
        .textStyle(TextStyles.bodyMedium)
        .foregroundStyle(Color.gray)
        .multilineTextAlignment(.center)
        .lineLimit(3)
    }
    .padding(EdgeInsets(top: 48, leading: 16, bottom: 24, trailing: 16))
    .frame(maxWidth: .infinity)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 20))
  }
}
