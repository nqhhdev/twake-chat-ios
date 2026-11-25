import Domain
import Foundation
import PeopleTestSupport
import Testing

@testable import People

@MainActor
struct ThirdPartyInviteTests {
  private let carol = ContactAddress.email("carol@example.org")!
  private let terms = IdentityPolicy(
    id: "privacy_policy", title: "Privacy Policy",
    url: URL(string: "https://id.example.org/privacy-en.html")!)

  private func search(
    _ identity: FakeIdentityRepository?, mode: PeopleSearchViewModel.Mode = .direct,
    people: FakePeopleRepository = FakePeopleRepository(),
    opened: @escaping @MainActor (String, String) -> Void = { _, _ in },
    invite: (@MainActor ([String]) async -> [String])? = nil,
    inviteAddresses: (@MainActor ([ContactAddress]) async -> [ContactAddress])? = nil
  ) -> PeopleSearchViewModel {
    PeopleSearchViewModel(
      mode: mode, repository: people, debounce: .seconds(60), onOpen: opened, invite: invite,
      identity: identity, inviteAddresses: inviteAddresses)
  }

  @Test func aTypedEmailWithAnAccountShowsThatPerson() async {
    let identity = FakeIdentityRepository()
    identity.known = [carol: "@carol:example.org"]
    let viewModel = search(identity)
    viewModel.query = " Carol@Example.org "
    await viewModel.search()
    #expect(
      viewModel.results == [Person(id: "@carol:example.org", displayName: "carol@example.org")])
    #expect(viewModel.typedAddress == nil)
    #expect(identity.lookups == [[carol]])
  }

  @Test func aTypedEmailWithoutAnAccountOffersAnInvitation() async {
    let identity = FakeIdentityRepository()
    let viewModel = search(identity)
    viewModel.query = "carol@example.org"
    await viewModel.search()
    #expect(viewModel.results.isEmpty)
    #expect(viewModel.typedAddress == carol)
    #expect(viewModel.offersAddressInvites)
  }

  @Test func withoutAnIdentityServerNoAddressIsOffered() async {
    let identity = FakeIdentityRepository()
    identity.serverStatus = .unavailable
    let viewModel = search(identity)
    viewModel.query = "carol@example.org"
    await viewModel.search()
    #expect(viewModel.typedAddress == nil)
    #expect(!viewModel.offersAddressInvites)
    #expect(identity.lookups.isEmpty)
    let none = search(nil)
    none.query = "carol@example.org"
    await none.search()
    #expect(none.typedAddress == nil)
  }

  @Test func nothingIsLookedUpBeforeTheTermsAreAccepted() async {
    let identity = FakeIdentityRepository()
    identity.serverStatus = .needsConsent(server: "id.example.org", policies: [terms])
    var opened: (String, String)?
    let viewModel = search(identity, opened: { opened = ($0, $1) })
    viewModel.query = "carol@example.org"
    await viewModel.search()
    #expect(viewModel.typedAddress == carol)
    #expect(identity.lookups.isEmpty)

    await viewModel.tap(carol)
    #expect(viewModel.consent == IdentityConsent(server: "id.example.org", policies: [terms]))
    #expect(identity.lookups.isEmpty)

    await viewModel.acceptConsent()
    #expect(identity.accepted == [[terms]])
    #expect(viewModel.consent == nil)
    #expect(identity.lookups == [[carol]])
    #expect(identity.directs == [carol])
    #expect(opened?.0 == "!direct-carol@example.org:example.org")
    #expect(opened?.1 == "carol@example.org")
  }

  @Test func decliningTheTermsSendsNothing() async {
    let identity = FakeIdentityRepository()
    identity.serverStatus = .needsConsent(server: "id.example.org", policies: [terms])
    let viewModel = search(identity)
    await viewModel.tap(carol)
    viewModel.declineConsent()
    #expect(viewModel.consent == nil)
    #expect(identity.lookups.isEmpty)
    #expect(identity.accepted.isEmpty)
    #expect(identity.directs.isEmpty)
  }

  @Test func tappingAnEmailWithAnAccountDraftsAChatWithThatPerson() async {
    let identity = FakeIdentityRepository()
    identity.known = [carol: "@carol:example.org"]
    let viewModel = search(identity)
    await viewModel.tap(carol)
    #expect(viewModel.draftChat?.id == "@carol:example.org")
    #expect(identity.directs.isEmpty)
  }

  @Test func aGroupInvitesThePickedAddressesOnceCreated() async {
    let identity = FakeIdentityRepository()
    let people = FakePeopleRepository()
    let viewModel = search(identity, mode: .group, people: people)
    await viewModel.tap(carol)
    #expect(viewModel.selectedAddresses == [carol])
    viewModel.groupName = "Team"
    #expect(viewModel.canCreateGroup)
    await viewModel.createGroup()
    #expect(people.createdGroups.first?.userIds == [])
    #expect(identity.invites.map(\.address) == [carol])
    #expect(identity.invites.first?.roomId == "!group")
  }

  @Test func tappingAPickedAddressAgainUnpicksIt() async {
    let viewModel = search(FakeIdentityRepository(), mode: .invite)
    await viewModel.tap(carol)
    await viewModel.tap(carol)
    #expect(viewModel.selectedAddresses.isEmpty)
  }

  @Test func inviteModeSendsAddressesAndKeepsTheOnesThatFailed() async {
    let identity = FakeIdentityRepository()
    let dave = ContactAddress.phone("+33 6 12 34 56 78", regionCode: nil)!
    var sent: [ContactAddress] = []
    let viewModel = search(
      identity, mode: .invite, invite: { _ in [] },
      inviteAddresses: { addresses in
        sent = addresses
        return [dave]
      })
    await viewModel.tap(carol)
    await viewModel.tap(dave)
    await viewModel.inviteSelected()
    #expect(sent == [carol, dave])
    #expect(viewModel.selectedAddresses == [dave])
    #expect(viewModel.errorMessage == "Could not invite +33612345678. The others were invited.")
    #expect(!viewModel.didInvite)
  }

  @Test func inviteModeClosesOnceEveryAddressIsInvited() async {
    let viewModel = search(
      FakeIdentityRepository(), mode: .invite, invite: { _ in [] },
      inviteAddresses: { _ in [] })
    await viewModel.tap(carol)
    await viewModel.inviteSelected()
    #expect(viewModel.didInvite)
  }
}

@MainActor
struct PhoneContactsViewModelTests {
  private let alice = AddressBookContact(
    id: "1", name: "Alice", emails: ["Alice@Example.org"], phones: ["06 11 22 33 44"])
  private let bob = AddressBookContact(
    id: "2", name: "Bob", emails: [], phones: ["+84 912 345 678"])
  private let nobody = AddressBookContact(
    id: "3", name: "Zed", emails: ["zed@example.org"], phones: [])

  @Test func nothingShowsWithoutAnIdentityServer() async {
    let identity = FakeIdentityRepository()
    identity.serverStatus = .unavailable
    let contacts = PhoneContactsViewModel(addressBook: FakeAddressBook(), identity: identity)
    await contacts.load()
    #expect(contacts.state == .hidden)
    let none = PhoneContactsViewModel(addressBook: FakeAddressBook(), identity: nil)
    await none.load()
    #expect(none.state == .hidden)
  }

  @Test func theAddressBookIsReadOnlyAfterTheUserAllowsIt() async {
    let book = FakeAddressBook(access: .notDetermined, entries: [alice])
    let identity = FakeIdentityRepository()
    let contacts = PhoneContactsViewModel(addressBook: book, identity: identity)
    await contacts.load()
    #expect(contacts.state == .askPermission)
    #expect(identity.lookups.isEmpty)
    await contacts.allowAccess()
    #expect(book.requests == 1)
    #expect(contacts.state == .loaded)
  }

  @Test func aRefusedPermissionSaysWhereToAllowIt() async {
    let book = FakeAddressBook(access: .notDetermined, grants: false)
    let contacts = PhoneContactsViewModel(addressBook: book, identity: FakeIdentityRepository())
    await contacts.load()
    await contacts.allowAccess()
    #expect(contacts.state == .denied)
  }

  @Test func theTermsComeBeforeAnyLookup() async {
    let identity = FakeIdentityRepository()
    let policy = IdentityPolicy(
      id: "tos", title: "Terms", url: URL(string: "https://id.example.org/tos")!)
    identity.serverStatus = .needsConsent(server: "id.example.org", policies: [policy])
    let contacts = PhoneContactsViewModel(
      addressBook: FakeAddressBook(entries: [alice]), identity: identity)
    await contacts.load()
    #expect(
      contacts.state == .needsConsent(IdentityConsent(server: "id.example.org", policies: [policy]))
    )
    #expect(identity.lookups.isEmpty)
    await contacts.acceptConsent()
    #expect(identity.accepted == [[policy]])
    #expect(contacts.state == .loaded)
  }

  @Test func contactsOnMatrixAndContactsToInviteAreSplit() async {
    let identity = FakeIdentityRepository()
    let alicePhone = ContactAddress.phone("+33611223344", regionCode: nil)!
    identity.known = [
      alicePhone: "@alice:example.org",
      ContactAddress.phone("+84912345678", regionCode: nil)!: "@bob:example.org",
    ]
    let contacts = PhoneContactsViewModel(
      addressBook: FakeAddressBook(entries: [nobody, bob, alice]), identity: identity)
    contacts.regionCode = "FR"
    await contacts.load()
    #expect(contacts.state == .loaded)
    #expect(contacts.onMatrix.map(\.userId) == ["@alice:example.org", "@bob:example.org"])
    #expect(contacts.onMatrix.first?.address == alicePhone)
    #expect(contacts.invitable.map(\.contact.name) == ["Zed"])
    #expect(contacts.invitable.first?.address == ContactAddress.email("zed@example.org"))
    #expect(Set(identity.lookups.first ?? []).count == 4)
    #expect(contacts.filtered(contacts.onMatrix, by: "bo").map(\.contact.name) == ["Bob"])
  }

  @Test func aFailedLookupCanBeTriedAgain() async {
    let identity = FakeIdentityRepository()
    identity.lookupFails = true
    let contacts = PhoneContactsViewModel(
      addressBook: FakeAddressBook(entries: [alice]), identity: identity)
    await contacts.load()
    #expect(contacts.state == .failed)
    identity.lookupFails = false
    await contacts.load()
    #expect(contacts.state == .loaded)
  }
}
