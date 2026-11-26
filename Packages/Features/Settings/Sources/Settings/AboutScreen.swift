import DesignSystem
import Domain
import SwiftUI

struct AboutScreen: View {
  var body: some View {
    List {
      Section {
        VStack(spacing: 8) {
          TwakeLogo(TwakeLogo.welcomeResource, width: 180, height: 118)
          Text("Version \(SettingsViewModel.appVersion)")
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
      }
      Section {
        Link("Privacy Policy", destination: URL(string: "https://twake.app/policy")!)
        Link(
          "Source code (AGPL-3.0)",
          destination: URL(string: "https://github.com/linagora/twake-on-matrix")!)
      }
    }
    .twakeTitle("About")
  }
}
