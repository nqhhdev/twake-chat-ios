import Foundation
@preconcurrency import Speech

struct SpeechTranscriber: VoiceTranscribing {
  func transcribe(fileURL: URL) async -> Result<String, TranscriptionFailure> {
    guard await Self.authorize() else { return .failure(.denied) }
    guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
      recognizer.supportsOnDeviceRecognition
    else { return .failure(.unavailable) }
    let request = SFSpeechURLRecognitionRequest(url: fileURL)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    let once = ResumeOnce()
    return await withCheckedContinuation { continuation in
      let task = recognizer.recognitionTask(with: request) { result, error in
        if let result, result.isFinal {
          once.resume(continuation, with: .success(result.bestTranscription.formattedString))
        } else if error != nil {
          once.resume(continuation, with: .failure(.failed))
        }
      }
      once.keep(task)
    }
  }

  static func authorize() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status == .authorized)
        }
      }
    default: return false
    }
  }
}

private final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var resumed = false
  private var task: SFSpeechRecognitionTask?

  func keep(_ task: SFSpeechRecognitionTask) {
    lock.withLock { self.task = task }
  }

  func resume(
    _ continuation: CheckedContinuation<Result<String, TranscriptionFailure>, Never>,
    with result: Result<String, TranscriptionFailure>
  ) {
    let first = lock.withLock {
      guard !resumed else { return false }
      resumed = true
      task = nil
      return true
    }
    if first { continuation.resume(returning: result) }
  }
}
