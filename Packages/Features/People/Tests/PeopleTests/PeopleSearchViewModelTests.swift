import Domain
import PeopleTestSupport
import Testing

@testable import People

@MainActor
struct PeopleSearchViewModelTests {
  private let alice = Person(id: "@alice:example.org", displayName: "Alice")
  private let bob = Person(id: "@bob:example.org", displayName: "Bob")

  private func viewModel(
    _ repository: FakePeopleRepository, mode: PeopleSearchViewModel.Mode = .direct,
    opened: @escaping @MainActor (String, String) -> Void = { _, _ in }
  ) -> PeopleSearchViewModel {
    PeopleSearchViewModel(
      mode: mode, repository: repository, debounce: .seconds(60), onOpen: opened)
  }

  @Test func searchingShowsThePeopleFound() async {
    let repository = FakePeopleRepository()
    repository.people = [alice, bob]
    let viewModel = viewModel(repository)
    viewModel.query = "ali"
    await viewModel.search()
    #expect(viewModel.results == [alice])
  }

  @Test func anEmptySearchClearsTheResultsWithoutAsking() async {
    let repository = FakePeopleRepository()
    let viewModel = viewModel(repository)
    viewModel.query = "  "
    await viewModel.search()
    #expect(viewModel.results.isEmpty)
    #expect(repository.searches.isEmpty)
  }

  @Test func aTapInDirectModeOpensTheChat() async {
    let repository = FakePeopleRepository()
    var opened: (String, String)?
    let viewModel = viewModel(repository) { opened = ($0, $1) }
    await viewModel.tap(alice)
    #expect(repository.directs == ["@alice:example.org"])
    #expect(opened?.0 == "!dm-@alice:example.org")
    #expect(opened?.1 == "Alice")
  }

  @Test func aGroupNeedsPeopleAndANameThenOpens() async {
    let repository = FakePeopleRepository()
    var openedName: String?
    let viewModel = viewModel(repository, mode: .group) { openedName = $1 }
    await viewModel.tap(alice)
    await viewModel.tap(bob)
    await viewModel.tap(bob)
    #expect(viewModel.selected == [alice])
    #expect(!viewModel.canCreateGroup)
    viewModel.groupName = " Team "
    #expect(viewModel.canCreateGroup)
    await viewModel.createGroup()
    #expect(repository.createdGroups.first?.name == "Team")
    #expect(repository.createdGroups.first?.userIds == ["@alice:example.org"])
    #expect(openedName == "Team")
  }

  @Test func switchingModeClearsTheSelection() async {
    let viewModel = viewModel(FakePeopleRepository(), mode: .group)
    await viewModel.tap(alice)
    viewModel.switchMode(.direct)
    #expect(viewModel.selected.isEmpty)
  }

  @Test func failuresShowAMessage() async {
    let repository = FakePeopleRepository()
    repository.fails = true
    let viewModel = viewModel(repository)
    await viewModel.tap(alice)
    #expect(viewModel.errorMessage == "Could not start the chat. Please try again.")
  }
}
