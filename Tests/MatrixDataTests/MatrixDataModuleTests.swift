import MatrixData
import Testing

struct MatrixDataModuleTests {
  @Test func dependsOnDomainAndAppShared() {
    #expect(MatrixDataModule.dependencies == ["Domain", "AppShared"])
  }
}
