import DesignSystem
import Network
import Observation
import SwiftUI

/// Whether the device has a network path, from `NWPathMonitor`, for the offline banner. It starts unknown (online), so
/// the banner never flashes at launch.
@MainActor @Observable
final class Connectivity {
  private(set) var isOffline = false
  @ObservationIgnored private let monitor = NWPathMonitor()

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let offline = path.status != .satisfied
      Task { @MainActor in
        guard let self, self.isOffline != offline else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self.isOffline = offline }
      }
    }
    monitor.start(queue: DispatchQueue(label: "org.linagora.twake.connectivity"))
  }

  isolated deinit {
    monitor.cancel()
  }
}

/// The bar under the title while do not disturb is on, with the button that turns it off.
struct DoNotDisturbBanner: View {
  let onTurnOff: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "moon.fill").foregroundStyle(.indigo)
        .symbolEffect(.bounce, options: .nonRepeating)
      Text(localized("Do Not Disturb is on. You get no notifications."))
        .textStyle(TextStyles.labelMedium)
      Spacer(minLength: 4)
      Button(localized("Turn Off"), action: onTurnOff)
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
    .foregroundStyle(SysColors.onSurface)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(SysColors.surfaceVariant)
    .transition(.move(edge: .top).combined(with: .opacity))
    .accessibilityElement(children: .combine)
  }
}

/// The bar under the title while the device is offline, as Messages and Telegram show it: messages wait to be sent
/// and the list may be out of date until the network comes back.
struct OfflineBanner: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "wifi.slash")
        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
      Text(localized("No connection. Messages will be sent when you are back online."))
        .textStyle(TextStyles.labelMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(SysColors.onSurface)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(SysColors.surfaceVariant)
    .transition(.move(edge: .top).combined(with: .opacity))
    .accessibilityElement(children: .combine)
  }
}
