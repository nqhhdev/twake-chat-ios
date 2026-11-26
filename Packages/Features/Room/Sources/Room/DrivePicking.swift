import Domain
import Foundation
import SwiftUI
import WebKit

struct DrivePickSession {
  enum Action: Equatable {
    case acknowledge(String)
    case ready
    case finish(DrivePickOutcome)
  }

  static let handlerName = "driveIntentMessage"
  static let readyTimeout: Duration = .seconds(20)
  static let shim = """
    (function() {
      if (window.self !== window.top) return;
      window.parent = {
        postMessage: function(data) {
          window.webkit.messageHandlers.driveIntentMessage.postMessage(
            typeof data === 'string' ? data : JSON.stringify(data)
          );
        }
      };
    })();
    """

  let picker: DrivePicker
  private(set) var isAcknowledged = false
  private(set) var isFinished = false

  init(picker: DrivePicker) {
    self.picker = picker
  }

  var acknowledgementScript: String {
    let client =
      (try? JSONSerialization.data(withJSONObject: picker.client, options: .fragmentsAllowed))
      .map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    return """
      window.dispatchEvent(new MessageEvent('message', {
        data: \(picker.acknowledgement),
        origin: \(client),
        source: window
      }));
      """
  }

  mutating func receive(_ raw: String, origin: String?, isMainFrame: Bool) -> Action? {
    guard !isFinished, isMainFrame, let origin, origin == picker.origin,
      let message = DrivePickerMessage.parse(raw, intentId: picker.intentId)
    else { return nil }
    switch message {
    case .ready:
      guard !isAcknowledged else { return .ready }
      isAcknowledged = true
      return .acknowledge(acknowledgementScript)
    case .readyToUse: return .ready
    case .done(let documents): return finish(documents.isEmpty ? .cancelled : .picked(documents))
    case .error: return finish(.failed)
    case .cancel: return finish(.cancelled)
    case .unknown: return nil
    }
  }

  mutating func timedOut() -> Action? {
    isAcknowledged ? nil : finish(.failed)
  }

  mutating func finish(_ outcome: DrivePickOutcome) -> Action? {
    guard !isFinished else { return nil }
    isFinished = true
    return .finish(outcome)
  }

  func allowsNavigation(to url: URL?) -> Bool {
    guard let url else { return false }
    if url.absoluteString == "about:blank" { return true }
    guard let origin = picker.origin else { return false }
    return DrivePicker.origin(scheme: url.scheme, host: url.host(), port: url.port) == origin
  }
}

struct DrivePickerScreen: View {
  let picker: DrivePicker
  let onFinish: @MainActor (DrivePickOutcome) -> Void

  @State private var isReady = false

  var body: some View {
    NavigationStack {
      DriveWebView(picker: picker, onReady: { isReady = true }, onFinish: onFinish)
        .ignoresSafeArea(edges: .bottom)
        .overlay {
          if !isReady { ProgressView() }
        }
        .navigationTitle(localized("Twake Drive"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(localized("Cancel")) { onFinish(.cancelled) }
          }
        }
    }
  }
}

struct DriveWebView: UIViewRepresentable {
  let picker: DrivePicker
  let onReady: @MainActor () -> Void
  let onFinish: @MainActor (DrivePickOutcome) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(session: DrivePickSession(picker: picker), onReady: onReady, onFinish: onFinish)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    let content = WKUserContentController()
    content.addUserScript(
      WKUserScript(
        source: DrivePickSession.shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    content.add(
      WeakDriveMessageHandler(target: context.coordinator), name: DrivePickSession.handlerName)
    configuration.userContentController = content
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    context.coordinator.start(webView)
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: DrivePickSession.handlerName)
    coordinator.stop()
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    private var session: DrivePickSession
    private let onReady: @MainActor () -> Void
    private let onFinish: @MainActor (DrivePickOutcome) -> Void
    private weak var webView: WKWebView?
    private var timeout: Task<Void, Never>?

    init(
      session: DrivePickSession, onReady: @escaping @MainActor () -> Void,
      onFinish: @escaping @MainActor (DrivePickOutcome) -> Void
    ) {
      self.session = session
      self.onReady = onReady
      self.onFinish = onFinish
    }

    func start(_ webView: WKWebView) {
      self.webView = webView
      webView.load(URLRequest(url: session.picker.url))
      timeout = Task { [weak self] in
        try? await Task.sleep(for: DrivePickSession.readyTimeout)
        guard !Task.isCancelled, let self else { return }
        self.apply(self.session.timedOut())
      }
    }

    func stop() {
      timeout?.cancel()
      timeout = nil
    }

    func received(_ message: WKScriptMessage) {
      guard let raw = message.body as? String else { return }
      let origin = message.frameInfo.securityOrigin
      apply(
        session.receive(
          raw,
          origin: DrivePicker.origin(scheme: origin.protocol, host: origin.host, port: origin.port),
          isMainFrame: message.frameInfo.isMainFrame))
    }

    private func apply(_ action: DrivePickSession.Action?) {
      switch action {
      case nil:
        return
      case .acknowledge(let script):
        stop()
        webView?.evaluateJavaScript(script)
        onReady()
      case .ready:
        onReady()
      case .finish(let outcome):
        stop()
        onFinish(outcome)
      }
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      guard navigationAction.targetFrame?.isMainFrame ?? true else { return .allow }
      return session.allowsNavigation(to: navigationAction.request.url) ? .allow : .cancel
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
      guard navigationResponse.isForMainFrame,
        let response = navigationResponse.response as? HTTPURLResponse,
        response.statusCode >= 400
      else { return .allow }
      apply(session.finish(.failed))
      return .cancel
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: any Error
    ) {
      loadFailed(error)
    }

    func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
    ) {
      loadFailed(error)
    }

    private func loadFailed(_ error: any Error) {
      let error = error as NSError
      let blockedByPolicy = error.domain == "WebKitErrorDomain" && error.code == 102
      guard error.code != NSURLErrorCancelled, !blockedByPolicy else { return }
      apply(session.finish(.failed))
    }
  }
}

@MainActor
private final class WeakDriveMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: DriveWebView.Coordinator?

  init(target: DriveWebView.Coordinator) {
    self.target = target
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.received(message)
  }
}
