import Domain
import Testing

struct ContactAddressTests {
  @Test func anEmailIsTrimmedAndLowercased() {
    let address = ContactAddress.email("  Alice@Example.ORG ")
    #expect(address?.address == "alice@example.org")
    #expect(address?.medium == "email")
    #expect(address?.matrixAddress == "alice@example.org")
  }

  @Test(arguments: ["@alice:example.org", "alice", "alice@example", "a b@example.org", "", "a@b."])
  func notAnEmail(_ text: String) {
    #expect(ContactAddress.email(text) == nil)
  }

  @Test func anInternationalNumberKeepsItsDigits() {
    #expect(ContactAddress.phone("+33 6-12.34/56 78", regionCode: "VN")?.address == "+33612345678")
    let plain = ContactAddress.phone("+33 6 12 34 56 78", regionCode: "VN")
    #expect(plain?.address == "+33612345678")
    #expect(plain?.medium == "msisdn")
    #expect(plain?.matrixAddress == "33612345678")
  }

  @Test func aDoubleZeroPrefixIsInternational() {
    #expect(ContactAddress.phone("0084 912 345 678", regionCode: nil)?.address == "+84912345678")
  }

  @Test func aNationalNumberTakesTheRegionCallingCode() {
    #expect(ContactAddress.phone("06 12 34 56 78", regionCode: "fr")?.address == "+33612345678")
    #expect(ContactAddress.phone("0912 345 678", regionCode: "VN")?.address == "+84912345678")
    #expect(ContactAddress.phone("(650) 555-1234", regionCode: "US")?.address == "+16505551234")
    #expect(ContactAddress.phone("1 650 555 1234", regionCode: "US")?.address == "+16505551234")
  }

  @Test func aNationalNumberWithoutAKnownRegionIsNotGuessed() {
    #expect(ContactAddress.phone("06 12 34 56 78", regionCode: nil) == nil)
    #expect(ContactAddress.phone("06 12 34 56 78", regionCode: "ZZ") == nil)
  }

  @Test(arguments: ["+33 6", "+1234567890123456", "abc", "+33 6 12 34 56 78 ext 2"])
  func notAPhoneNumber(_ text: String) {
    #expect(ContactAddress.phone(text, regionCode: "FR") == nil)
  }

  @Test func parsingPrefersAnEmail() {
    #expect(ContactAddress.parse("bob@example.org", regionCode: "FR")?.kind == .email)
    #expect(ContactAddress.parse("+33612345678", regionCode: nil)?.kind == .phone)
    #expect(ContactAddress.parse("Bob", regionCode: "FR") == nil)
  }

  @Test func aContactGivesEachAddressOnce() {
    let contact = AddressBookContact(
      id: "1", name: "Alice", emails: ["alice@example.org", "ALICE@example.org", "nope"],
      phones: ["+33 6 12 34 56 78", "06 12 34 56 78"])
    #expect(
      contact.addresses(regionCode: "FR").map(\.address) == ["alice@example.org", "+33612345678"])
  }
}
