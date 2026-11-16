import Testing

@testable import Domain

@Suite struct ComposerCommandTests {
  @Test func aTextWithoutASlashIsAMessage() {
    #expect(ComposerCommand.prepare("hello") == .message("hello"))
    #expect(ComposerCommand.prepare("see /tmp") == .message("see /tmp"))
  }

  @Test func aPathIsNotACommand() {
    #expect(ComposerCommand.prepare("/usr/bin is full") == .message("/usr/bin is full"))
  }

  @Test func meSendsAnEmote() {
    #expect(ComposerCommand.prepare("/me waves") == .emote("waves"))
    #expect(ComposerCommand.prepare("/ME  waves") == .emote("waves"))
  }

  @Test func meWithoutATextIsNotSent() {
    #expect(ComposerCommand.prepare("/me") == .unknown("me"))
  }

  @Test func shrugAddsTheShrug() {
    #expect(ComposerCommand.prepare("/shrug") == .message(ComposerCommand.shrug))
    #expect(
      ComposerCommand.prepare("/shrug no idea") == .message("no idea " + ComposerCommand.shrug))
  }

  @Test func twoSlashesSendOne() {
    #expect(ComposerCommand.prepare("//me waves") == .message("/me waves"))
  }

  @Test func anotherWordIsUnknown() {
    #expect(ComposerCommand.prepare("/Nope now") == .unknown("nope"))
  }
}
