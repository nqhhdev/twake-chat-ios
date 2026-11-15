import Foundation

/// A poll (MSC3381, `m.poll.start`), as the timeline shows it: its question, its answers with who chose each, and
/// whether the results show before it ends. Votes are the latest `m.poll.response` of each person, as the SDK counts
/// them; the end (`m.poll.end`) freezes them.
public struct Poll: Sendable, Equatable {
  public struct Answer: Sendable, Equatable, Identifiable {
    /// The answer id the poll was created with; a vote names it.
    public let id: String
    public let text: String
    /// The Matrix ids of the people who chose it.
    public let voterIds: [String]

    public init(id: String, text: String, voterIds: [String] = []) {
      self.id = id
      self.text = text
      self.voterIds = voterIds
    }
  }

  public let question: String
  public let answers: [Answer]
  /// How many answers one person may choose; 1 for a single choice.
  public let maxSelections: Int
  /// The results show as people vote (`disclosed`); otherwise only once the poll ends.
  public let isDisclosed: Bool
  public let isEnded: Bool
  /// The answers the user chose.
  public let ownAnswerIds: Set<String>

  public init(
    question: String, answers: [Answer], maxSelections: Int = 1, isDisclosed: Bool = true,
    isEnded: Bool = false, ownAnswerIds: Set<String> = []
  ) {
    self.question = question
    self.answers = answers
    self.maxSelections = max(1, maxSelections)
    self.isDisclosed = isDisclosed
    self.isEnded = isEnded
    self.ownAnswerIds = ownAnswerIds
  }

  /// How many people voted, each counted once however many answers they chose.
  public var voterCount: Int {
    Set(answers.flatMap(\.voterIds)).count
  }

  /// The results show: the poll ended, or it is disclosed and the user voted.
  public var showsResults: Bool {
    isEnded || (isDisclosed && !ownAnswerIds.isEmpty)
  }

  /// The share of the voters who chose `answer`, 0…1.
  public func share(of answer: Answer) -> Double {
    let voters = voterCount
    return voters == 0 ? 0 : Double(answer.voterIds.count) / Double(voters)
  }

  /// The answers with the most votes, once the poll ended; empty before, or when nobody voted.
  public var winningAnswerIds: Set<String> {
    guard isEnded, let top = answers.map(\.voterIds.count).max(), top > 0 else { return [] }
    return Set(answers.filter { $0.voterIds.count == top }.map(\.id))
  }

  /// The answers the user chooses when tapping `answerId`: a single-choice poll swaps the choice; a multiple-choice
  /// poll adds or removes it, keeping at most `maxSelections` (the oldest choice goes when full).
  public func selection(tapping answerId: String) -> [String] {
    if maxSelections == 1 { return [answerId] }
    var chosen = answers.map(\.id).filter { ownAnswerIds.contains($0) }
    if let index = chosen.firstIndex(of: answerId) {
      chosen.remove(at: index)
    } else {
      chosen.append(answerId)
      if chosen.count > maxSelections { chosen.removeFirst() }
    }
    return chosen
  }
}

/// A poll the user writes, before it is sent.
public struct PollDraft: Sendable, Equatable {
  public var question: String
  public var answers: [String]
  public var allowsMultipleChoices: Bool
  /// Results show only once the poll ends (`undisclosed`).
  public var hidesResults: Bool

  public init(
    question: String = "", answers: [String] = ["", ""], allowsMultipleChoices: Bool = false,
    hidesResults: Bool = false
  ) {
    self.question = question
    self.answers = answers
    self.allowsMultipleChoices = allowsMultipleChoices
    self.hidesResults = hidesResults
  }

  /// At most 20 answers, as the MSC allows.
  public static let maxAnswers = 20

  /// The non-empty answers, trimmed.
  public var cleanAnswers: [String] {
    answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// A question and at least two answers.
  public var canSend: Bool {
    !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cleanAnswers.count >= 2
  }
}
