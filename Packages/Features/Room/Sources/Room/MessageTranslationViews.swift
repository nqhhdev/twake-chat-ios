import DesignSystem
import Domain
import SwiftUI
import Translation

struct MessageTranslationTask: ViewModifier {
  let message: TimelineMessage
  let viewModel: RoomViewModel
  @State private var configuration: TranslationSession.Configuration?

  private var isTranslating: Bool { viewModel.translation(of: message) == .translating }

  func body(content: Content) -> some View {
    let id = message.eventId
    let text = RoomViewModel.translationSource(of: message)
    let viewModel = viewModel
    return
      content
      .onChange(of: isTranslating, initial: true) { _, translating in
        guard translating else { return }
        if configuration == nil {
          configuration = TranslationSession.Configuration(target: Locale.current.language)
        } else {
          configuration?.invalidate()
        }
      }
      .translationTask(configuration) { @concurrent session in
        guard let id, let text else { return }
        let translated = try? await session.translate(text).targetText
        await viewModel.finishTranslation(of: id, text: translated)
      }
  }
}

struct TranslatedText: View {
  let text: String
  let showOriginal: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(text)
        .italic()
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 6) {
        Text("TRANSLATED")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(SysColors.textSecondary)
        Button("Show original", action: showOriginal)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(SysColors.primary)
          .buttonStyle(.plain)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint("Translated on this device")
  }
}
