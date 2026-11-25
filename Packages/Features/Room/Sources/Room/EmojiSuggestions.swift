import DesignSystem
import Domain
import SwiftUI

extension RoomViewModel {
  public var emojiSuggestions: [EmojiShortcode] {
    EmojiShortcode.suggestions(for: draft)
  }

  public func pickEmoji(_ suggestion: EmojiShortcode) {
    draft = EmojiShortcode.replacingQuery(in: draft, with: suggestion.emoji)
  }
}

struct EmojiSuggestions: View {
  let suggestions: [EmojiShortcode]
  let onPick: (EmojiShortcode) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(suggestions) { suggestion in
        Button {
          onPick(suggestion)
        } label: {
          HStack(spacing: 10) {
            Text(suggestion.emoji)
              .font(.title3)
              .frame(width: 32, height: 32)
            Text(":" + suggestion.shortcode + ":")
              .textStyle(TextStyles.bodyMedium)
              .foregroundStyle(SysColors.onSurface)
              .lineLimit(1)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 12)
          .frame(height: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .accessibilityLabel(suggestion.shortcode.replacingOccurrences(of: "_", with: " "))
        .accessibilityValue(suggestion.emoji)
      }
    }
    .background(.regularMaterial, in: .rect(cornerRadius: 14))
    .clipShape(.rect(cornerRadius: 14))
    .shadow(color: .black.opacity(0.10), radius: 8, y: -2)
    .padding(.horizontal, 12)
    .padding(.bottom, 4)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Emojis")
  }
}
