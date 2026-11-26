import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

final class FakeDrive: TwakeDriveRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _available = true
  private var _signedIn: Bool
  private var _pickerError: DriveError?
  private var _downloadError: DriveError?
  private var _calls: [String] = []
  private var _options: [DrivePickerOptions] = []
  let picker = DrivePicker(
    intentId: "i1", url: URL(string: "https://alice-drive.example.org/#/intents?intent=i1")!,
    client: "https://chat.example.org", acknowledgement: #"{"theme":{"type":"light"}}"#)
  let request = DriveSignInRequest(
    url: URL(string: "https://sso.example.org/authorize")!, callbackScheme: "twake.chat",
    state: "s1")

  init(signedIn: Bool = true) { _signedIn = signedIn }

  var available: Bool {
    get { lock.withLock { _available } }
    set { lock.withLock { _available = newValue } }
  }
  var pickerError: DriveError? {
    get { lock.withLock { _pickerError } }
    set { lock.withLock { _pickerError = newValue } }
  }
  var downloadError: DriveError? {
    get { lock.withLock { _downloadError } }
    set { lock.withLock { _downloadError = newValue } }
  }
  var calls: [String] { lock.withLock { _calls } }
  var options: [DrivePickerOptions] { lock.withLock { _options } }

  private func record(_ call: String) { lock.withLock { _calls.append(call) } }

  func isAvailable() async -> Bool { available }

  func signInRequest() async throws(DriveError) -> DriveSignInRequest {
    record("signInRequest")
    return request
  }

  func completeSignIn(_ request: DriveSignInRequest, callback: URL) async throws(DriveError) {
    record("completeSignIn \(callback.absoluteString)")
    lock.withLock { _signedIn = true }
  }

  func picker(_ options: DrivePickerOptions) async throws(DriveError) -> DrivePicker {
    record("picker")
    lock.withLock { _options.append(options) }
    if let error = pickerError { throw error }
    guard lock.withLock({ _signedIn }) else { throw .notSignedIn }
    return picker
  }

  func download(_ document: DriveDocument, maxBytes: Int?) async throws(DriveError) -> URL {
    record("download \(document.id)")
    if let error = downloadError { throw error }
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: document.name)
    try? Data("x".utf8).write(to: file)
    return file
  }

  func signOut() async { record("signOut") }
}

@MainActor
struct DrivePickingTests {
  private func room(
    _ drive: FakeDrive?,
    authenticate:
      @escaping @MainActor @Sendable (DriveSignInRequest)
      async throws(DriveError) -> URL = { _ throws(DriveError) in
        URL(string: "twake.chat://login?code=c&state=s1")!
      }
  ) -> (RoomViewModel, FakeTimelineRepository) {
    let timeline = FakeTimelineRepository()
    let access = drive.map { DriveAccess(repository: $0, authenticate: authenticate) }
    let room = RoomViewModel(
      roomId: "!r:example.org", roomName: "News", repository: timeline,
      media: FakeMediaRepository(), drive: access)
    return (room, timeline)
  }

  private func document(
    _ id: String, mimeType: String? = "application/pdf", sharing: String? = nil,
    download: String? = nil
  ) -> DriveDocument {
    DriveDocument(
      id: id, name: "\(id).pdf", size: 1, mimeType: mimeType,
      sharingLink: sharing.flatMap(URL.init(string:)),
      downloadLink: download.flatMap(URL.init(string:)))
  }

  @Test func theEntryShowsOnlyWhenTheServerOffersDrive() async {
    let (none, _) = room(nil)
    await none.loadDriveAvailability()
    #expect(!none.driveAvailable)
    #expect(await none.openDrive(isDark: false) == nil)
    let off = FakeDrive()
    off.available = false
    let (hidden, _) = room(off)
    await hidden.loadDriveAvailability()
    #expect(!hidden.driveAvailable)
    let (shown, _) = room(FakeDrive())
    await shown.loadDriveAvailability()
    #expect(shown.driveAvailable)
  }

  @Test func aSignedInAccountOpensThePickerWithTheLabels() async throws {
    let drive = FakeDrive()
    let (room, _) = room(drive)
    await room.loadDriveAvailability()
    let picker = await room.openDrive(isDark: true)
    #expect(picker == drive.picker)
    #expect(drive.calls == ["picker"])
    let options = try #require(drive.options.first)
    #expect(options.linkLabel == "Add as link")
    #expect(options.attachLabel == "Add as attachment")
    #expect(options.isDark)
    #expect(!room.isOpeningDrive)
  }

  @Test func theFirstPickSignsInThenOpensThePicker() async {
    let drive = FakeDrive(signedIn: false)
    let (room, _) = room(drive)
    await room.loadDriveAvailability()
    #expect(await room.openDrive(isDark: false) == drive.picker)
    #expect(
      drive.calls == [
        "picker", "signInRequest", "completeSignIn twake.chat://login?code=c&state=s1", "picker",
      ])
  }

  @Test func aCancelledSignInSaysNothing() async {
    let drive = FakeDrive(signedIn: false)
    let (room, _) = room(drive) { _ throws(DriveError) in throw .cancelled }
    await room.loadDriveAvailability()
    #expect(await room.openDrive(isDark: false) == nil)
    #expect(room.errorMessage == nil)
    #expect(drive.calls == ["picker", "signInRequest"])
  }

  @Test func aDriveWithoutTheChatAppTellsTheUserToAskTheirAdministrator() async {
    let drive = FakeDrive()
    drive.pickerError = .chatAppMissing
    let (room, _) = room(drive)
    await room.loadDriveAvailability()
    #expect(await room.openDrive(isDark: false) == nil)
    #expect(room.errorMessage?.contains("administrator") == true)
  }

  @Test func pickedLinksAreSentAsOneMessage() async {
    let (room, timeline) = room(FakeDrive())
    await room.finishDrivePick(
      .picked([
        document("a", sharing: "https://d.example.org/s/a"),
        document("b", sharing: "https://d.example.org/s/b"),
      ]))
    #expect(
      timeline.calls == [
        .send("[a.pdf](https://d.example.org/s/a)\n[b.pdf](https://d.example.org/s/b)")
      ])
    #expect(room.errorMessage == nil)
  }

  @Test func pickedFilesAreDownloadedAndSentAsAttachments() async {
    let drive = FakeDrive()
    let (room, timeline) = room(drive)
    await room.finishDrivePick(
      .picked([
        document("a", download: "https://d.example.org/a"),
        document("p", mimeType: "image/png", download: "https://d.example.org/p"),
      ]))
    #expect(drive.calls == ["download a", "download p"])
    let kinds = timeline.calls.compactMap { call -> OutgoingAttachment.Kind? in
      if case .attachment(let attachment) = call { return attachment.kind }
      return nil
    }
    #expect(kinds == [.file, .image(width: nil, height: nil)])
    #expect(room.uploadCount == 0)
  }

  @Test func aFailedDownloadIsTold() async {
    let drive = FakeDrive()
    drive.downloadError = .tooLarge
    let (room, timeline) = room(drive)
    await room.finishDrivePick(.picked([document("a", download: "https://d.example.org/a")]))
    #expect(timeline.calls.isEmpty)
    #expect(room.errorMessage == RoomViewModel.driveDownloadFailed)
  }

  @Test func shortcutsAndFailuresAreTold() async {
    let (room, timeline) = room(FakeDrive())
    await room.finishDrivePick(
      .picked([
        DriveDocument(
          id: "u", name: "site.url", size: 1, mimeType: nil, sharingLink: nil,
          downloadLink: URL(string: "https://d.example.org/u"))
      ]))
    #expect(room.errorMessage == RoomViewModel.driveShortcutsNotSent)
    await room.finishDrivePick(.failed)
    #expect(room.errorMessage == RoomViewModel.driveCouldNotOpen)
    await room.finishDrivePick(.cancelled)
    #expect(timeline.calls.isEmpty)
  }
}

struct DrivePickSessionTests {
  private let picker = DrivePicker(
    intentId: "i1", url: URL(string: "https://alice-drive.example.org/#/intents?intent=i1")!,
    client: "https://chat.example.org", acknowledgement: #"{"theme":{"type":"light"}}"#)
  private let origin = "https://alice-drive.example.org"

  @Test func readyIsAcknowledgedOnceWithTheConfigAndTheClient() {
    var session = DrivePickSession(picker: picker)
    let ready = #"{"type":"intent-i1:ready"}"#
    guard case .acknowledge(let script) = session.receive(ready, origin: origin, isMainFrame: true)
    else {
      Issue.record("ready was not acknowledged")
      return
    }
    #expect(script.contains(#"data: {"theme":{"type":"light"}}"#))
    #expect(script.contains(#"origin: "https:\/\/chat.example.org""#))
    #expect(session.receive(ready, origin: origin, isMainFrame: true) == .ready)
    #expect(session.timedOut() == nil)
  }

  @Test func messagesFromAnotherOriginOrFrameAreIgnored() {
    var session = DrivePickSession(picker: picker)
    let cancel = #"{"type":"intent-i1:cancel"}"#
    #expect(session.receive(cancel, origin: "https://evil.example.org", isMainFrame: true) == nil)
    #expect(session.receive(cancel, origin: origin, isMainFrame: false) == nil)
    #expect(session.receive(cancel, origin: nil, isMainFrame: true) == nil)
    #expect(session.receive(cancel, origin: origin, isMainFrame: true) == .finish(.cancelled))
    #expect(session.receive(cancel, origin: origin, isMainFrame: true) == nil)
  }

  @Test func donePicksAndAnEmptyDoneCancels() {
    var picked = DrivePickSession(picker: picker)
    let done =
      #"{"type":"intent-i1:done","document":[{"id":"a","name":"a.pdf","size":1,"sharingLink":"https://d.example.org/s/a"}]}"#
    guard
      case .finish(.picked(let documents)) =
        picked.receive(done, origin: origin, isMainFrame: true)
    else {
      Issue.record("done did not finish with the pick")
      return
    }
    #expect(documents.map(\.id) == ["a"])
    var empty = DrivePickSession(picker: picker)
    #expect(
      empty.receive(#"{"type":"intent-i1:done","document":[]}"#, origin: origin, isMainFrame: true)
        == .finish(.cancelled))
    var failed = DrivePickSession(picker: picker)
    #expect(
      failed.receive(#"{"type":"intent-i1:error"}"#, origin: origin, isMainFrame: true)
        == .finish(.failed))
  }

  @Test func aPageThatNeverGetsReadyTimesOut() {
    var session = DrivePickSession(picker: picker)
    #expect(session.timedOut() == .finish(.failed))
    #expect(session.timedOut() == nil)
  }

  @Test func thePageStaysOnTheIntentOrigin() {
    let session = DrivePickSession(picker: picker)
    #expect(session.allowsNavigation(to: URL(string: "https://alice-drive.example.org/x")))
    #expect(session.allowsNavigation(to: URL(string: "https://alice-drive.example.org:443/x")))
    #expect(session.allowsNavigation(to: URL(string: "about:blank")))
    #expect(!session.allowsNavigation(to: URL(string: "https://evil.example.org/")))
    #expect(!session.allowsNavigation(to: URL(string: "http://alice-drive.example.org/")))
    #expect(!session.allowsNavigation(to: URL(string: "javascript:alert(1)")))
    #expect(!session.allowsNavigation(to: nil))
  }
}
