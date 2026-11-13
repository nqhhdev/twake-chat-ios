import AppShared
import Domain
import MatrixRustSDK

/// Marks the MatrixData module. The proxies arrive with the features that need them (ADR 0006, ADR 0011).
public enum MatrixDataModule {
  public static let dependencies = [DomainModule.name, AppSharedModule.name]
}
