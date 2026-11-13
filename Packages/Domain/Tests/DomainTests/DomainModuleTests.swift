import Domain
import Testing

struct DomainModuleTests {
  @Test func nameIsTheModuleName() {
    #expect(DomainModule.name == "Domain")
  }
}
