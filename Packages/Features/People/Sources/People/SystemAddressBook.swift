import Contacts
import Domain
import Foundation

public struct SystemAddressBook: AddressBook {
  public init() {}

  public func access() async -> AddressBookAccess {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .notDetermined: .notDetermined
    case .authorized, .limited: .granted
    case .denied, .restricted: .denied
    @unknown default: .denied
    }
  }

  public func requestAccess() async -> Bool {
    (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
  }

  public func contacts() async -> [AddressBookContact] {
    await Task.detached(priority: .userInitiated) {
      let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
      ]
      var found: [AddressBookContact] = []
      try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) {
        contact, _ in
        let emails = contact.emailAddresses.map { $0.value as String }
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        guard !emails.isEmpty || !phones.isEmpty else { return }
        let name =
          CNContactFormatter.string(from: contact, style: .fullName) ?? emails.first ?? phones[0]
        found.append(
          AddressBookContact(id: contact.identifier, name: name, emails: emails, phones: phones))
      }
      return found
    }.value
  }
}
