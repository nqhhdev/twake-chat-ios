import Domain
import Foundation
import SwiftUI
import Testing

@testable import TwakeChat

/// Background and foreground: the banner rule for the chat on screen, and resume after a pause.
@MainActor
struct AppLifecycleTests {
  @Test func noBannerForTheChatOnScreen() {
    let push = PushCenter(repository: nil)
    #expect(push.showsBanner(forRoom: "!a:example.org"))
    push.openRoomId = "!a:example.org"
    #expect(!push.showsBanner(forRoom: "!a:example.org"))
    #expect(push.showsBanner(forRoom: "!b:example.org"))
    #expect(push.showsBanner(forRoom: nil))
  }

  private actor RecordingSync: SyncLifecycle {
    private(set) var calls: [String] = []
    func pauseSync() async { calls.append("pause") }
    func resumeSync() async { calls.append("resume") }
  }

  @Test func comingBackWithoutAPauseDoesNotResume() async {
    let sync = RecordingSync()
    let lifecycle = AppLifecycle(sync: sync, push: PushCenter(repository: nil))
    lifecycle.phaseChanged(to: .active)
    for _ in 0..<50 { await Task.yield() }
    #expect(await sync.calls.isEmpty)
  }
}
