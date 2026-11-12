import AppShared
import Domain

/// Marks the MatrixData module. The Matrix SDK dependency and the proxies arrive with a later slice.
public enum MatrixDataModule {
  public static let dependencies = [DomainModule.name, AppSharedModule.name]
}
