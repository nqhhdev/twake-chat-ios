import Foundation

public enum AccountDeletion: Sendable, Equatable {
  case done
  case needsConfirmation(DeviceAuthChallenge)
}

public protocol AccountDeletionRepository: Sendable {
  func deactivateAccount(auth: DeviceAuth?) async throws(DevicesError) -> AccountDeletion
}
