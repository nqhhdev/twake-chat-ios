import AVFoundation
import DesignSystem
import SwiftUI
import UIKit

enum CameraAccess: Equatable {
  case checking, granted, denied, unavailable

  static func current() async -> CameraAccess {
    guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return .granted
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    default: return .denied
    }
  }
}

struct QRScannerSheet: View {
  let error: String?
  let onCode: @MainActor (String) -> Void
  @State private var access = CameraAccess.checking
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(localized("Scan QR code"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(localized("Cancel")) { dismiss() }
          }
        }
    }
    .task { access = await CameraAccess.current() }
  }

  @ViewBuilder private var content: some View {
    switch access {
    case .checking:
      ProgressView()
    case .granted:
      ZStack(alignment: .bottom) {
        QRCodeScanner(onCode: onCode).ignoresSafeArea(edges: .bottom)
        RoundedRectangle(cornerRadius: 24)
          .strokeBorder(.white, lineWidth: 4)
          .frame(width: 240, height: 240)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityHidden(true)
        Text(error ?? localized("Point the camera at a Twake Chat or Matrix QR code."))
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(12)
          .background(
            error == nil
              ? AnyShapeStyle(Color.black.opacity(0.6))
              : AnyShapeStyle(SysColors.error.opacity(0.9))
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .padding(24)
          .animation(.default, value: error)
      }
    case .denied:
      ContentUnavailableView {
        Label(localized("Camera access is off"), systemImage: "camera")
      } description: {
        Text(localized("Allow Twake Chat to use the camera in Settings to scan QR codes."))
      } actions: {
        Button(localized("Open Settings")) {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      }
    case .unavailable:
      ContentUnavailableView(
        localized("No camera"), systemImage: "camera",
        description: Text(localized("This device has no camera to scan QR codes.")))
    }
  }
}

struct QRCodeScanner: UIViewControllerRepresentable {
  let onCode: @MainActor (String) -> Void

  func makeUIViewController(context: Context) -> QRScannerController {
    QRScannerController(onCode: onCode)
  }

  func updateUIViewController(_ controller: QRScannerController, context: Context) {
    controller.onCode = onCode
  }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onCode: @MainActor (String) -> Void
  private let capture = CaptureSession()
  private var preview: AVCaptureVideoPreviewLayer?
  private var lastCode: String?

  init(onCode: @escaping @MainActor (String) -> Void) {
    self.onCode = onCode
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    guard capture.configure(delegate: self) else { return }
    let layer = AVCaptureVideoPreviewLayer(session: capture.session)
    layer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(layer)
    preview = layer
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    capture.start()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    capture.stop()
  }

  nonisolated func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    let code = metadataObjects.lazy
      .compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
      .first
    guard let code else { return }
    MainActor.assumeIsolated { found(code) }
  }

  private func found(_ code: String) {
    guard code != lastCode else { return }
    lastCode = code
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    onCode(code)
  }
}

private final class CaptureSession: @unchecked Sendable {
  let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "QRCodeScanner.capture")

  func configure(delegate: any AVCaptureMetadataOutputObjectsDelegate) -> Bool {
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else { return false }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return false }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(delegate, queue: .main)
    output.metadataObjectTypes = [.qr]
    return true
  }

  func start() {
    queue.async { if !self.session.isRunning { self.session.startRunning() } }
  }

  func stop() {
    queue.async { if self.session.isRunning { self.session.stopRunning() } }
  }
}
