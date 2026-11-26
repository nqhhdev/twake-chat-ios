import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
public final class AppGridViewModel {
  public private(set) var apps: [TwakeApp] = []

  @ObservationIgnored private let capabilities: any ServerCapabilitiesRepository

  public init(capabilities: any ServerCapabilitiesRepository) {
    self.capabilities = capabilities
  }

  public func load() async {
    apps = await capabilities.current().build.apps
  }
}

struct AppGridRow: View {
  let viewModel: AppGridViewModel

  var body: some View {
    if !viewModel.apps.isEmpty {
      Section {
        NavigationLink {
          AppGridScreen(apps: viewModel.apps)
        } label: {
          SettingsRow(title: localized("Twake Apps"), icon: "square.grid.3x3", detail: nil)
        }
        .accessibilityIdentifier("settings.appGrid")
      }
    }
  }
}

struct AppGridScreen: View {
  let apps: [TwakeApp]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 24) {
        ForEach(apps) { app in
          Link(destination: app.url) {
            VStack(spacing: 8) {
              Image(systemName: app.symbol ?? "app")
                .font(.system(size: 28))
                .foregroundStyle(SysColors.onPrimary)
                .frame(width: 64, height: 64)
                .background(SysColors.primary, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
              Text(app.name)
                .textStyle(TextStyles.bodyMedium)
                .foregroundStyle(SysColors.onSurface)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            }
          }
          .accessibilityIdentifier("appGrid.\(app.id)")
        }
      }
      .padding()
    }
    .navigationTitle(localized("Twake Apps"))
  }
}
