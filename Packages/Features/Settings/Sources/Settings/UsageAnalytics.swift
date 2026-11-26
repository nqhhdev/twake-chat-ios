import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
public final class UsageAnalyticsViewModel {
  public private(set) var state: Analytics.State = .unavailable
  public private(set) var errorMessage: String?
  public var isPrompting = false

  @ObservationIgnored private let analytics: Analytics

  public init(analytics: Analytics) {
    self.analytics = analytics
  }

  public var isGranted: Bool { state == .granted }

  public func start() async {
    state = await analytics.state()
    isPrompting = state == .askConsent
    await analytics.startSession()
  }

  public func load() async {
    state = await analytics.state()
  }

  public func choose(_ granted: Bool) async {
    errorMessage = nil
    do {
      try await analytics.setConsent(granted)
      isPrompting = false
    } catch {
      errorMessage = localized("Could not save your choice. Please try again.")
    }
    state = await analytics.state()
  }
}

struct UsageAnalyticsSection: View {
  let viewModel: UsageAnalyticsViewModel

  var body: some View {
    if viewModel.state != .unavailable {
      Section {
        Toggle(
          isOn: Binding(
            get: { viewModel.isGranted },
            set: { granted in Task { await viewModel.choose(granted) } })
        ) {
          SettingsRow(title: localized("Share Usage Data"), icon: "chart.bar", detail: nil)
        }
        .accessibilityIdentifier("settings.usageAnalytics")
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      } footer: {
        Text(UsageAnalyticsText.explanation)
      }
    }
  }
}

enum UsageAnalyticsText {
  static let explanation =
    localized(
      "Twake Chat counts which screens and actions you use, to improve the app. It never sends your messages, names, contacts or files."
    )
}

public struct UsageAnalyticsConsentSheet: View {
  let viewModel: UsageAnalyticsViewModel

  public init(viewModel: UsageAnalyticsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "chart.bar.doc.horizontal")
        .font(.system(size: 40))
        .foregroundStyle(SysColors.primary)
        .accessibilityHidden(true)
      Text(localized("Help improve Twake Chat"))
        .textStyle(TextStyles.titleLarge)
        .foregroundStyle(SysColors.onSurface)
      Text(UsageAnalyticsText.explanation)
        .textStyle(TextStyles.bodyMedium)
        .foregroundStyle(SysColors.textSecondary)
        .multilineTextAlignment(.center)
      if let message = viewModel.errorMessage {
        Text(message).foregroundStyle(SysColors.error)
      }
      Button {
        Task { await viewModel.choose(true) }
      } label: {
        Text(localized("Share Usage Data")).frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("analytics.accept")
      Button {
        Task { await viewModel.choose(false) }
      } label: {
        Text(localized("Don't Share")).frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .accessibilityIdentifier("analytics.decline")
    }
    .padding(24)
    .presentationDetents([.medium])
  }
}

extension View {
  public func usageAnalyticsPrompt(_ viewModel: UsageAnalyticsViewModel?, isBlocked: Bool)
    -> some View
  {
    task { await viewModel?.start() }
      .sheet(
        isPresented: Binding(
          get: { !isBlocked && viewModel?.isPrompting == true },
          set: { if !$0 { viewModel?.isPrompting = false } })
      ) {
        if let viewModel { UsageAnalyticsConsentSheet(viewModel: viewModel) }
      }
  }
}
