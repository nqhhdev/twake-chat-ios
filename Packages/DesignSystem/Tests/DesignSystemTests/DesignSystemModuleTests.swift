import DesignSystem
import Testing

struct DesignSystemModuleTests {
  @Test func nameIsTheModuleName() {
    #expect(DesignSystemModule.name == "DesignSystem")
  }
}
