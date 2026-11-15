import DesignSystem
import Domain
import SwiftUI

/// A poll inside its bubble (MSC3381): the question, then each answer as a row the user taps to vote. Once the results
/// show (the user voted in a disclosed poll, or it ended), each row fills with its share of the votes, springing to
/// the new value as votes arrive; the winning answers of an ended poll are marked.
struct PollView: View {
  let poll: Poll
  let message: TimelineMessage
  let viewModel: RoomViewModel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: poll.isEnded ? "chart.bar.xaxis" : "chart.bar")
          .foregroundStyle(SysColors.primary)
        Text(poll.question)
          .textStyle(TextStyles.titleSmall)
          .foregroundStyle(SysColors.onSurface)
          .fixedSize(horizontal: false, vertical: true)
      }
      ForEach(poll.answers) { answer in
        answerRow(answer)
      }
      Text(footer)
        .textStyle(TextStyles.labelSmall)
        .foregroundStyle(SysColors.textSecondary)
        .contentTransition(.numericText(value: Double(poll.voterCount)))
    }
    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: poll)
    .sensoryFeedback(.selection, trigger: poll.ownAnswerIds)
  }

  private var footer: String {
    let votes = poll.voterCount == 1 ? "1 vote" : "\(poll.voterCount) votes"
    if poll.isEnded { return "Final results · \(votes)" }
    if !poll.isDisclosed { return "Results will show when the poll ends" }
    if poll.ownAnswerIds.isEmpty {
      return poll.maxSelections > 1 ? "Choose up to \(poll.maxSelections) · \(votes)" : votes
    }
    return votes
  }

  private func answerRow(_ answer: Poll.Answer) -> some View {
    let chosen = poll.ownAnswerIds.contains(answer.id)
    let won = poll.winningAnswerIds.contains(answer.id)
    let share = poll.showsResults ? poll.share(of: answer) : 0
    return Button {
      guard viewModel.focus == nil else { return }
      Task { await viewModel.vote(answer.id, in: message) }
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(chosen ? SysColors.primary : SysColors.textSecondary)
            .contentTransition(.symbolEffect(.replace))
          Text(answer.text)
            .textStyle(won ? TextStyles.labelLarge : TextStyles.bodyMedium)
            .foregroundStyle(SysColors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
          if won {
            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
              .transition(.scale.combined(with: .opacity))
          }
          if poll.showsResults {
            Text("\(answer.voterIds.count)")
              .textStyle(TextStyles.labelMedium)
              .foregroundStyle(SysColors.textSecondary)
              .contentTransition(.numericText(value: Double(answer.voterIds.count)))
          }
        }
        GeometryReader { proxy in
          Capsule().fill(SysColors.textSecondary.opacity(0.15))
            .overlay(alignment: .leading) {
              Capsule()
                .fill(
                  won || chosen
                    ? AnyShapeStyle(SysColors.primary)
                    : AnyShapeStyle(SysColors.textSecondary.opacity(0.6))
                )
                .frame(width: proxy.size.width * share)
            }
        }
        .frame(height: 5)
        .opacity(poll.showsResults ? 1 : 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(poll.isEnded || message.eventId == nil)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(answer.text)
    .accessibilityValue(
      poll.showsResults ? "\(answer.voterIds.count) votes\(chosen ? ", your choice" : "")" : ""
    )
    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
  }
}

/// Writes a poll, as the "+" menu offers it: a question, two to twenty answers (a new empty row appears as the last one
/// fills), one or several choices, and results shown live or only at the end.
struct CreatePollSheet: View {
  let viewModel: RoomViewModel

  @State private var draft = PollDraft()
  @State private var isSending = false
  @FocusState private var focused: Int?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Question") {
          TextField("Ask a question", text: $draft.question, axis: .vertical)
            .focused($focused, equals: -1)
            .submitLabel(.next)
        }
        Section {
          ForEach(draft.answers.indices, id: \.self) { index in
            HStack {
              TextField("Option \(index + 1)", text: answerBinding(index))
                .focused($focused, equals: index)
                .submitLabel(.next)
                .onSubmit { focused = index + 1 < draft.answers.count ? index + 1 : nil }
              if draft.answers.count > 2 {
                Button {
                  withAnimation { _ = draft.answers.remove(at: index) }
                } label: {
                  Image(systemName: "minus.circle.fill").foregroundStyle(SysColors.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove option \(index + 1)")
              }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
          }
        } header: {
          Text("Options")
        } footer: {
          Text("Up to \(PollDraft.maxAnswers) options.")
        }
        Section {
          Toggle("Multiple answers", isOn: $draft.allowsMultipleChoices)
          Toggle("Hide results until the end", isOn: $draft.hidesResults)
        }
      }
      .navigationTitle("New Poll")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send") {
            isSending = true
            Task {
              if await viewModel.createPoll(draft) { dismiss() }
              isSending = false
            }
          }
          .disabled(!draft.canSend || isSending)
        }
      }
      .onAppear { focused = -1 }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  /// Typing in the last option adds a new empty one under it, until the limit.
  private func answerBinding(_ index: Int) -> Binding<String> {
    Binding {
      index < draft.answers.count ? draft.answers[index] : ""
    } set: { text in
      guard index < draft.answers.count else { return }
      draft.answers[index] = text
      if index == draft.answers.count - 1, !text.isEmpty,
        draft.answers.count < PollDraft.maxAnswers
      {
        withAnimation(.snappy) { draft.answers.append("") }
      }
    }
  }
}
