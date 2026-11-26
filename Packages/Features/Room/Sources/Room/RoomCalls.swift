import DesignSystem
import Domain
import SwiftUI
import WebKit

struct RoomCallButton: View {
  let calls: RoomCallViewModel
  let title: String

  var body: some View {
    if calls.isOpening {
      ProgressView()
    } else {
      Button(calls.actionTitle, systemImage: calls.state.isActive ? "video.fill" : "video") {
        Task { await calls.open(title: title) }
      }
      .tint(calls.state.isActive ? .green : nil)
      .accessibilityIdentifier(A11yIdentifiers.room.callButton)
    }
  }
}

struct ActiveCallBanner: View {
  let calls: RoomCallViewModel
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "video.fill")
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(Circle().fill(.green))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(localized("Call in progress"))
          .textStyle(TextStyles.titleSmall)
          .foregroundStyle(SysColors.onSurface)
        Text(participants)
          .textStyle(TextStyles.bodySmall)
          .foregroundStyle(SysColors.textSecondary)
      }
      Spacer(minLength: 8)
      Button(calls.activeCall == nil ? localized("Join") : localized("Return to call")) {
        Task { await calls.open(title: title) }
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .controlSize(.small)
      .disabled(calls.isOpening)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
    .accessibilityElement(children: .combine)
  }

  private var participants: String {
    switch calls.participantCount {
    case 0: localized("Starting")
    default: localized("\(calls.participantCount) people")
    }
  }
}

public struct CallOverlay: View {
  static let minimizedSize = CGSize(width: 120, height: 180)

  let center: CallCenter

  public init(center: CallCenter = .shared) {
    self.center = center
  }

  public var body: some View {
    if let call = center.call {
      let minimized = center.isMinimized
      ElementCallWebView(call: call) { message in
        Task { await center.fromWidget(message) }
      }
      .id(call.id)
      .background(Color.black)
      .accessibilityHidden(minimized)
      .frame(
        width: minimized ? Self.minimizedSize.width : nil,
        height: minimized ? Self.minimizedSize.height : nil
      )
      .clipShape(RoundedRectangle(cornerRadius: minimized ? 12 : 0))
      .overlay {
        if minimized {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { center.restore() }
            .accessibilityElement()
            .accessibilityLabel(localized("Return to call"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { center.restore() }
        }
      }
      .overlay(alignment: .top) {
        if !minimized { controls }
      }
      .shadow(radius: minimized ? 8 : 0)
      .padding(.trailing, minimized ? 16 : 0)
      .padding(.bottom, minimized ? 96 : 0)
      .frame(
        maxWidth: .infinity, maxHeight: .infinity,
        alignment: minimized ? .bottomTrailing : .center
      )
      .ignoresSafeArea(edges: minimized ? [] : .all)
      .animation(.spring(response: 0.35, dampingFraction: 0.85), value: minimized)
    }
  }

  private var controls: some View {
    HStack {
      Button {
        center.minimize()
      } label: {
        Image(systemName: "chevron.down")
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(localized("Minimize call"))
      Spacer()
      Button {
        Task { await center.end() }
      } label: {
        Image(systemName: "phone.down.fill")
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(Circle().fill(.red))
      }
      .accessibilityLabel(localized("Leave call"))
    }
    .padding(.horizontal, 8)
    .safeAreaPadding(.top)
  }
}

struct ElementCallWebView: UIViewRepresentable {
  static let handlerName = "twakeCall"
  static let bridgeScript = """
    window.addEventListener('message', function (event) {
      var data = event.data;
      if (!data || typeof data !== 'object') { return; }
      var fromWidget = data.api === 'fromWidget' && !data.response;
      var answerToWidget = data.api === 'toWidget' && data.response;
      if (fromWidget || answerToWidget) {
        window.webkit.messageHandlers.twakeCall.postMessage(JSON.stringify(data));
      }
    }, false);
    """

  let call: ActiveCall
  let onMessage: @MainActor (String) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(call: call, onMessage: onMessage) }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    let content = WKUserContentController()
    content.addUserScript(
      WKUserScript(
        source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    content.add(WeakMessageHandler(target: context.coordinator), name: Self.handlerName)
    configuration.userContentController = content
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isOpaque = false
    webView.backgroundColor = .black
    webView.uiDelegate = context.coordinator
    context.coordinator.attach(webView)
    webView.load(URLRequest(url: call.url))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    coordinator.stop()
  }

  @MainActor
  final class Coordinator: NSObject, WKUIDelegate {
    private let call: ActiveCall
    private let onMessage: @MainActor (String) -> Void
    private weak var webView: WKWebView?
    private var forwarding: Task<Void, Never>?

    init(call: ActiveCall, onMessage: @escaping @MainActor (String) -> Void) {
      self.call = call
      self.onMessage = onMessage
    }

    func attach(_ webView: WKWebView) {
      self.webView = webView
      let session = call.session
      forwarding = Task { [weak self] in
        for await message in await session.messagesToWidget() {
          self?.send(message)
        }
      }
    }

    func stop() {
      forwarding?.cancel()
      forwarding = nil
    }

    func received(_ body: Any) {
      guard let text = body as? String else { return }
      onMessage(text)
    }

    private func send(_ message: String) {
      webView?.evaluateJavaScript("window.postMessage(\(message), '*')")
    }

    func webView(
      _ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
      initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
      origin.host == call.url.host() ? .grant : .deny
    }
  }
}

@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: ElementCallWebView.Coordinator?

  init(target: ElementCallWebView.Coordinator) {
    self.target = target
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.received(message.body)
  }
}

struct RoomCallPresentation: ViewModifier {
  let calls: RoomCallViewModel?
  let roomId: String
  let title: String

  func body(content: Content) -> some View {
    content
      .task(id: roomId) {
        guard let calls else { return }
        await calls.load()
        guard calls.isAvailable else { return }
        await calls.joinIfAnswered(title: title)
        await calls.watch()
      }
      .alert(
        calls?.errorMessage ?? "",
        isPresented: Binding(
          get: { calls?.errorMessage != nil }, set: { if !$0 { calls?.errorMessage = nil } })
      ) {
        Button(localized("OK"), role: .cancel) {}
      }
  }

}

extension View {
  func roomCalls(_ calls: RoomCallViewModel?, roomId: String, title: String) -> some View {
    modifier(RoomCallPresentation(calls: calls, roomId: roomId, title: title))
  }
}
