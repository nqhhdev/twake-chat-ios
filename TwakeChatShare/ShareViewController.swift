import AppShared
import Intents
import ObjectiveC
import UIKit
import UniformTypeIdentifiers

/// The "Twake Chat" entry of the system share sheet (Flutter `TwakeShareExtension`, `receive_sharing_intent`). It shows
/// no screen of its own: it copies what was shared (pictures, videos, files, text and web links) into the App Group
/// inbox, opens the app with `twake.chat://share`, and closes; the app asks which chat to send it to. Running the
/// Matrix SDK here would not fit an extension's memory, so the app sends. Nothing here logs: the items are the user's.
final class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await share() }
  }

  private func share() async {
    guard let inbox = SharedInbox.inAppGroup(), let folder = try? inbox.begin() else {
      return close()
    }
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    var texts: [String] = []
    var files: [SharedItems.File] = []
    for provider in providers {
      switch await Self.read(provider, into: folder) {
      case .text(let text): texts.append(text)
      case .file(let file): files.append(file)
      case nil: continue
      }
    }
    let items = SharedItems(
      text: texts.isEmpty ? nil : texts.joined(separator: "\n"), files: files,
      roomId: (extensionContext?.intent as? INSendMessageIntent)?.conversationIdentifier,
      accountUserId: Self.accountUserId(of: extensionContext?.intent as? INSendMessageIntent))
    guard !items.isEmpty, (try? inbox.finish(items)) != nil else {
      inbox.clear()
      return close()
    }
    openApp()
    close()
  }

  private static func accountUserId(of intent: INSendMessageIntent?) -> String? {
    guard let intent else { return nil }
    return AccountLabel.accountUserId(
      senderIsMe: intent.sender?.isMe == true, senderId: intent.sender?.customIdentifier,
      meRecipientId: intent.recipients?.first(where: \.isMe)?.customIdentifier)
  }

  private enum Read {
    case text(String)
    case file(SharedItems.File)
  }

  /// One shared item: a picture, video or file is copied into the folder; a web link or text is kept as text.
  private static func read(_ provider: NSItemProvider, into folder: URL) async -> Read? {
    let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
    if let type = types.first(where: { $0.conforms(to: .image) }) {
      return await copy(provider, type: type, kind: .image, into: folder).map(Read.file)
    }
    if let type = types.first(where: { $0.conforms(to: .movie) }) {
      return await copy(provider, type: type, kind: .video, into: folder).map(Read.file)
    }
    if types.contains(where: { $0.conforms(to: .url) && !$0.conforms(to: .fileURL) }),
      let url = await object(URL.self, from: provider), !url.isFileURL
    {
      return .text(url.absoluteString)
    }
    if types.contains(where: { $0.conforms(to: .plainText) }),
      let text = await object(String.self, from: provider)
    {
      return .text(text)
    }
    if let type = types.first(where: { $0.conforms(to: .data) || $0.conforms(to: .fileURL) }) {
      return await copy(provider, type: type, kind: .file, into: folder).map(Read.file)
    }
    return nil
  }

  /// Copies the provider's file into the folder under its own name, made unique.
  private static func copy(
    _ provider: NSItemProvider, type: UTType, kind: SharedItems.File.Kind, into folder: URL
  ) async -> SharedItems.File? {
    await withCheckedContinuation { continuation in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        guard let url else { return continuation.resume(returning: nil) }
        let name = "\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)"
        let target = folder.appending(path: name)
        let ok = (try? FileManager.default.copyItem(at: url, to: target)) != nil
        continuation.resume(returning: ok ? SharedItems.File(name: name, kind: kind) : nil)
      }
    }
  }

  private static func object<T: _ObjectiveCBridgeable & Sendable>(
    _ type: T.Type, from provider: NSItemProvider
  ) async -> T? where T._ObjectiveCType: NSItemProviderReading {
    await withCheckedContinuation { continuation in
      _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
    }
  }

  /// Opens the app through the responder chain, as `receive_sharing_intent` does: an extension may not call
  /// `UIApplication.open`, so the application found in the chain is asked through the Objective-C runtime.
  private func openApp() {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if current is UIApplication,
        let method = class_getInstanceMethod(type(of: current), selector)
      {
        typealias Open =
          @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let open = unsafeBitCast(method_getImplementation(method), to: Open.self)
        open(current, selector, SharedInbox.openURL as NSURL, NSDictionary(), nil)
        return
      }
      responder = current.next
    }
  }

  private func close() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}
