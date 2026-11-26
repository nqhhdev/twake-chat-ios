import Domain
import Foundation
import UniformTypeIdentifiers

public struct DriveAccess: Sendable {
  public let repository: any TwakeDriveRepository
  public let authenticate: @MainActor @Sendable (DriveSignInRequest) async throws(DriveError) -> URL

  public init(
    repository: any TwakeDriveRepository,
    authenticate: @escaping @MainActor @Sendable (DriveSignInRequest) async throws(DriveError) -> URL
  ) {
    self.repository = repository
    self.authenticate = authenticate
  }
}

enum DrivePickOutcome: Equatable {
  case picked([DriveDocument])
  case cancelled
  case failed
}

extension RoomViewModel {
  static let driveCouldNotOpen = "Couldn't open Twake Drive"
  static let driveShortcutsNotSent = "Shortcuts can't be attached, send a link instead"
  static let driveDownloadFailed = "Some files couldn't be added from Twake Drive"

  func loadDriveAvailability() async {
    driveAvailable = await drive?.repository.isAvailable() ?? false
  }

  func openDrive(isDark: Bool) async -> DrivePicker? {
    guard let drive, driveAvailable, !isOpeningDrive else { return nil }
    isOpeningDrive = true
    defer { isOpeningDrive = false }
    errorMessage = nil
    let options = DrivePickerOptions(
      linkLabel: "Add as link", attachLabel: "Add as attachment",
      maxAttachmentBytes: await media.maxUploadSize(), isDark: isDark)
    do {
      return try await Self.picker(drive, options: options)
    } catch {
      errorMessage = Self.driveFailureMessage(error)
      return nil
    }
  }

  static func picker(_ drive: DriveAccess, options: DrivePickerOptions) async throws(DriveError)
    -> DrivePicker
  {
    do throws(DriveError) {
      return try await drive.repository.picker(options)
    } catch {
      guard error == .notSignedIn else { throw error }
    }
    let request = try await drive.repository.signInRequest()
    let callback = try await drive.authenticate(request)
    try await drive.repository.completeSignIn(request, callback: callback)
    return try await drive.repository.picker(options)
  }

  static func driveFailureMessage(_ error: DriveError) -> String? {
    switch error {
    case .cancelled: nil
    case .notSignedIn, .signInFailed, .workplaceUnknown: "Couldn't sign in to Twake Drive"
    case .chatAppMissing:
      "Twake Chat isn't installed on your Twake Drive yet. Ask your administrator to install it."
    case .unavailable, .exchangeRejected, .intentFailed, .tooLarge, .downloadFailed:
      driveCouldNotOpen
    }
  }

  func finishDrivePick(_ outcome: DrivePickOutcome) async {
    switch outcome {
    case .cancelled: return
    case .failed: errorMessage = Self.driveCouldNotOpen
    case .picked(let documents): await send(drivePlan: DrivePickPlan.plan(documents))
    }
  }

  func send(drivePlan plan: DrivePickPlan) async {
    errorMessage = nil
    switch plan {
    case .nothingToSend:
      errorMessage = Self.driveCouldNotOpen
    case .shortcutsOnly:
      errorMessage = Self.driveShortcutsNotSent
    case .links(let texts):
      sendCount += 1
      for text in texts {
        do {
          try await repository.send(text: text)
        } catch {
          errorMessage = Self.driveCouldNotOpen
          return
        }
      }
    case .attach(let documents, let skippedShortcuts):
      let failed = await sendDriveFiles(documents)
      if failed {
        errorMessage = Self.driveDownloadFailed
      } else if skippedShortcuts > 0 {
        errorMessage = Self.driveShortcutsNotSent
      }
    }
  }

  private func sendDriveFiles(_ documents: [DriveDocument]) async -> Bool {
    guard let drive else { return !documents.isEmpty }
    let limit = await media.maxUploadSize()
    var files: [(DriveDocument, URL)] = []
    var failed = false
    uploadCount += 1
    for document in documents {
      do {
        files.append((document, try await drive.repository.download(document, maxBytes: limit)))
      } catch {
        failed = true
      }
    }
    uploadCount -= 1
    for (document, file) in files {
      await send(
        attachment: Self.driveKind(document), fileURL: file, mimeType: document.mimeType,
        size: document.size)
      try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
    return failed
  }

  static func driveKind(_ document: DriveDocument) -> OutgoingAttachment.Kind {
    let type =
      document.mimeType.flatMap { UTType(mimeType: $0) }
      ?? UTType(filenameExtension: (document.name as NSString).pathExtension)
    return AttachmentLoader.kind(of: type)
  }
}
