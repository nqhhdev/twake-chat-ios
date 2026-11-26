import Domain
import Foundation
import MatrixRustSDK

extension TimelineProxy {
  public func canSchedule() async -> Bool {
    guard let opened, threadRoot == nil,
      (try? await opened.room.latestEncryptionState()) == .notEncrypted
    else { return false }
    if let delayedEventsSupported { return delayedEventsSupported }
    if let capabilities {
      let supported = await capabilities.current().supports(DelayedEvents.feature)
      delayedEventsSupported = supported
      return supported
    }
    guard
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "", version: "versions"),
      let versions = await ClientServerRequest.object(request)
    else { return false }
    let supported = DelayedEvents.supports(versions)
    delayedEventsSupported = supported
    return supported
  }

  public func schedule(text: String, at date: Date, replyTo: String?) async throws(ScheduleError) {
    guard let opened else { throw .failed }
    guard (try? await opened.room.latestEncryptionState()) == .notEncrypted else {
      throw .encryptedRoom
    }
    guard await canSchedule() else { throw .unsupported }
    let room = ClientServerRequest.encode(roomId)
    let path =
      "rooms/\(room)/send/m.room.message/\(UUID().uuidString)?\(DelayedEvents.delayParameter)="
      + String(DelayedEvents.delay(until: date))
    guard
      let request = ClientServerRequest.make(
        client: opened.client.client, path: path, method: "PUT",
        json: DelayedEvents.content(text: text, replyTo: replyTo, emotes: knownEmotes)),
      let (status, body) = await ClientServerRequest.answer(request)
    else { throw .failed }
    guard status == 200 else { throw DelayedEvents.error(status: status, body: body) }
  }

  public func scheduledMessages() async -> [ScheduledMessage] {
    guard let opened,
      let request = ClientServerRequest.make(
        client: opened.client.client, path: "delayed_events?status=scheduled",
        version: DelayedEvents.version),
      let object = await ClientServerRequest.object(request)
    else { return [] }
    return DelayedEvents.scheduled(object, roomId: roomId)
  }

  public func cancelScheduled(id: String) async -> Bool {
    await updateDelayedEvent(id: id, action: "cancel")
  }

  public func sendScheduledNow(id: String) async -> Bool {
    await updateDelayedEvent(id: id, action: "send")
  }

  private func updateDelayedEvent(id: String, action: String) async -> Bool {
    guard let client = opened?.client.client else { return false }
    let delay = ClientServerRequest.encode(id)
    if let request = ClientServerRequest.make(
      client: client, path: "delayed_events/\(delay)/\(action)", method: "POST", json: [:],
      version: DelayedEvents.version),
      let (status, _) = await ClientServerRequest.answer(request)
    {
      if status == 200 { return true }
      guard status == 404 || status == 400 || status == 405 else { return false }
    }
    guard
      let request = ClientServerRequest.make(
        client: client, path: "delayed_events/\(delay)", method: "POST",
        json: ["action": action], version: DelayedEvents.version)
    else { return false }
    return await ClientServerRequest.succeeds(request)
  }
}
