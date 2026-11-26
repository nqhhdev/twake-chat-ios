import Domain
import Foundation
import PeopleTestSupport
import Testing

@testable import People

@MainActor
struct TwakeContactsViewModelTests {
  private let bob = AddressBookEntry(id: "1", userId: "@bob:example.org", displayName: "Bob")
  private let ann = AddressBookEntry(id: "2", userId: "@ann:example.org", displayName: "ann")
  private let gone = AddressBookEntry(
    id: "3", userId: "@gone:example.org", displayName: "Gone", active: false)

  @Test func withoutToMNothingIsShownOrAsked() async {
    let repository = FakeTwakeContactsRepository(features: .none)
    repository.entries = [bob]
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    #expect(contacts.features == .none)
    #expect(contacts.entries.isEmpty)
    #expect(!(await contacts.invite(ContactAddress.email("a@b.org")!)))
    await contacts.makeLink()
    #expect(contacts.link == nil)
    #expect(repository.links.isEmpty)
  }

  @Test func theAddressBookIsSortedByNameWithoutInactiveContacts() async {
    let repository = FakeTwakeContactsRepository()
    repository.entries = [bob, gone, ann]
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    #expect(contacts.entries == [ann, bob])
    #expect(contacts.filtered(by: "BO") == [bob])
    #expect(contacts.filtered(by: "@ann") == [ann])
    #expect(contacts.entry(forUserId: "@bob:example.org") == bob)
  }

  @Test func addingChecksTheMatrixIdAndTheName() async {
    let repository = FakeTwakeContactsRepository()
    repository.entries = [bob]
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    #expect(!(await contacts.add(userId: "carol", displayName: "Carol")))
    #expect(contacts.errorMessage == "Enter a Matrix ID such as @alice:example.org.")
    #expect(!(await contacts.add(userId: "@carol:example.org", displayName: "  ")))
    #expect(contacts.errorMessage == "Enter a name.")
    #expect(!(await contacts.add(userId: "@bob:example.org", displayName: "Bobby")))
    #expect(contacts.errorMessage == "@bob:example.org is already in your contacts.")
    #expect(await contacts.add(userId: " @carol:example.org ", displayName: " Carol "))
    #expect(contacts.errorMessage == nil)
    #expect(contacts.entries.map(\.displayName) == ["Bob", "Carol"])
    #expect(repository.entries.last?.userId == "@carol:example.org")
  }

  @Test func renamingAndRemovingChangeTheList() async {
    let repository = FakeTwakeContactsRepository()
    repository.entries = [bob, ann]
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    #expect(await contacts.rename(bob, to: "Albert"))
    #expect(contacts.entries.map(\.displayName) == ["Albert", "ann"])
    await contacts.remove(ann)
    #expect(contacts.entries.map(\.userId) == ["@bob:example.org"])
    repository.failure = .requestFailed
    await contacts.remove(contacts.entries[0])
    #expect(contacts.entries.count == 1)
    #expect(contacts.errorMessage == "Could not remove Albert.")
  }

  @Test func anInvitationIsSentOncePerAddress() async {
    let repository = FakeTwakeContactsRepository()
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    let carol = ContactAddress.email("carol@example.org")!
    #expect(await contacts.invite(carol))
    #expect(contacts.invited[carol] == "inv1")
    #expect(!(await contacts.invite(carol)))
    #expect(repository.sent == [carol])
  }

  @Test func tooManyInvitationsSaySo() async {
    let repository = FakeTwakeContactsRepository()
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    repository.failure = .tooManyRequests
    #expect(!(await contacts.invite(ContactAddress.phone("+33612345678", regionCode: nil)!)))
    #expect(contacts.errorMessage == "Too many invitations sent. Please try again later.")
  }

  @Test func aLinkIsMadeWithoutAContact() async {
    let repository = FakeTwakeContactsRepository()
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    await contacts.makeLink()
    #expect(contacts.link?.url.absoluteString == "https://chat.example.org/?invite=link1")
    #expect(repository.links == [nil])
  }

  @Test func invitationsListNewestFirstAndRefreshOne() async {
    let repository = FakeTwakeContactsRepository()
    let older = TwakeInvitation(
      id: "a", recipient: "a@b.org", kind: .email, expiration: Date(timeIntervalSince1970: 10),
      accessed: false, userId: nil)
    let newer = TwakeInvitation(
      id: "b", recipient: "+33612345678", kind: .phone,
      expiration: Date(timeIntervalSince1970: 20), accessed: true, userId: nil)
    repository.storedInvitations = [older, newer]
    let contacts = TwakeContactsViewModel(repository: repository)
    await contacts.load()
    await contacts.loadInvitations()
    #expect(contacts.invitations?.map(\.id) == ["b", "a"])
    let joined = TwakeInvitation(
      id: "a", recipient: "a@b.org", kind: .email, expiration: older.expiration, accessed: true,
      userId: "@a:example.org")
    repository.storedInvitations = [joined, newer]
    await contacts.refresh(older)
    #expect(contacts.invitations?.last == joined)
  }

  @Test func anInvitationTellsItsStatus() {
    let now = Date(timeIntervalSince1970: 100)
    func invitation(_ expiration: Double?, accessed: Bool, userId: String?) -> TwakeInvitation {
      TwakeInvitation(
        id: "x", recipient: "a@b.org", kind: .email,
        expiration: expiration.map(Date.init(timeIntervalSince1970:)), accessed: accessed,
        userId: userId)
    }
    #expect(
      invitation(50, accessed: true, userId: "@a:b").status(now: now) == .joined(userId: "@a:b"))
    #expect(invitation(50, accessed: true, userId: nil).status(now: now) == .expired)
    #expect(invitation(200, accessed: true, userId: nil).status(now: now) == .opened)
    #expect(invitation(200, accessed: false, userId: "").status(now: now) == .pending)
    #expect(invitation(nil, accessed: false, userId: nil).status(now: now) == .pending)
  }
}
