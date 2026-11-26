import Domain
import Foundation
import Testing

@testable import TwakeChat

@MainActor
struct SessionPromptTests {
  private actor Checks {
    private var answers: [SessionWarning?]
    private(set) var count = 0

    init(_ answers: [SessionWarning?]) { self.answers = answers }

    func next() -> SessionWarning? {
      count += 1
      return answers.isEmpty ? nil : answers.removeFirst()
    }
  }

  private func makePrompt() -> SessionPrompt { SessionPrompt(sleep: { _ in }) }

  @Test func offersTheWarningOnceACheckReportsIt() async {
    let checks = Checks([nil, .unverified])
    let prompt = makePrompt()
    await prompt.start(checking: { await checks.next() })
    #expect(prompt.warning == .unverified)
    #expect(await checks.count == 2)
  }

  @Test func staysHiddenWhenTheSessionCanReadEverything() async {
    let checks = Checks([nil, nil])
    let prompt = makePrompt()
    await prompt.start(checking: { await checks.next() })
    #expect(prompt.warning == nil)
    #expect(await checks.count == SessionPrompt.pauses.count)
  }

  @Test func laterHidesItForTheRestOfTheSignIn() async {
    let checks = Checks([.recoveryIncomplete, .recoveryIncomplete])
    let prompt = makePrompt()
    await prompt.start(checking: { await checks.next() })
    #expect(prompt.warning == .recoveryIncomplete)
    prompt.dismiss()
    #expect(prompt.warning == nil)
    await prompt.start(checking: { await checks.next() })
    #expect(prompt.warning == nil)
  }

  @Test func aSessionFixedFromTheBannerClearsIt() async {
    let checks = Checks([.unverified, nil])
    let prompt = makePrompt()
    await prompt.start(checking: { await checks.next() })
    #expect(prompt.warning == .unverified)
    await prompt.refresh(checking: { await checks.next() })
    #expect(prompt.warning == nil)
  }

  @Test func withoutACheckThereIsNothingToOffer() async {
    let prompt = makePrompt()
    await prompt.start(checking: nil)
    #expect(prompt.warning == nil)
  }
}
