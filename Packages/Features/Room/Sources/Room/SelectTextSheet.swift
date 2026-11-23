import DesignSystem
import SwiftUI

/// "Select Text" from the message menu: the message's text in a sheet, where the system selection picks any part of it
/// to copy, as WhatsApp and Telegram offer. A long press on the bubble opens the menu, so it cannot select there.
struct SelectTextSheet: View {
  let text: AttributedString
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      SelectableText(text)
        .navigationTitle("Select Text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .presentationDetents([.medium, .large])
  }
}
