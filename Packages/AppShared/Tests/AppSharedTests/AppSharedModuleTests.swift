import AppShared
import Testing

struct AppSharedModuleTests {
  @Test func nameIsTheModuleName() {
    #expect(AppSharedModule.name == "AppShared")
  }
}
