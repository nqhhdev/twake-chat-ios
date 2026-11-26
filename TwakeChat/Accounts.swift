import AppShared
import Foundation
import MatrixData
import Observation
import SwiftUI

@MainActor @Observable
final class AccountsCoordinator {
  enum Notice: Equatable {
    case alreadyAdded(String)
    case full

    var message: String {
      switch self {
      case .alreadyAdded(let userId): "\(userId) is already signed in on this device."
      case .full: "You can add up to \(AccountList.maximum) accounts."
      }
    }
  }

  typealias MakeRoot =
    @MainActor (AccountSlot, @escaping @Sendable (SessionChange) -> Void) -> RootCoordinator

  private(set) var root: RootCoordinator
  private(set) var rootSlot: AccountSlot
  private(set) var list: AccountList
  private(set) var adding: RootCoordinator?
  var notice: Notice?

  @ObservationIgnored private(set) var addingSlot: AccountSlot?
  @ObservationIgnored private let registry: AccountRegistry
  @ObservationIgnored private let makeRoot: MakeRoot
  @ObservationIgnored private let relay: SessionRelay

  init(registry: AccountRegistry, legacyUserId: String?, makeRoot: @escaping MakeRoot) {
    let list = registry.migrate(legacyUserId: legacyUserId)
    let slot = list.active?.slot ?? list.slotForSignIn()
    let relay = SessionRelay()
    self.registry = registry
    self.makeRoot = makeRoot
    self.relay = relay
    self.list = list
    rootSlot = slot
    root = makeRoot(slot, relay.forward(slot))
    relay.target = self
    AppDelegate.push = root.push
  }

  var canAddAccount: Bool { !list.isFull && adding == nil }

  var activeUserId: String? { list.account(slot: rootSlot)?.userId }

  func switchTo(userId: String) {
    guard let record = list.account(userId: userId), record.slot != rootSlot else { return }
    registry.update { $0.activate(userId: userId) }
    reloadList()
    install(makeRoot(record.slot, relay.forward(record.slot)), slot: record.slot)
  }

  func startAddingAccount() {
    guard canAddAccount else { return }
    let slot = list.slotForSignIn()
    addingSlot = slot
    adding = makeRoot(slot, relay.forward(slot))
  }

  func cancelAddingAccount() async {
    guard let adding, let slot = addingSlot else { return }
    self.adding = nil
    addingSlot = nil
    await adding.retire()
    if list.account(slot: slot) == nil {
      try? FileManager.default.removeItem(at: registry.storeDirectory(for: slot))
    }
  }

  func sessionChanged(_ change: SessionChange, in slot: AccountSlot) async {
    switch change {
    case .signedIn(let userId):
      let result = registry.update { $0.add(userId: userId, slot: slot) }
      reloadList()
      guard slot == addingSlot, let added = adding else { return }
      adding = nil
      addingSlot = nil
      switch result {
      case .added:
        install(added, slot: slot)
      case .alreadyAdded, .full:
        notice = result == .full ? .full : .alreadyAdded(userId)
        await added.discardSession()
        await added.retire()
      }
    case .signedOut:
      registry.update { _ = $0.remove(slot: slot) }
      reloadList()
      guard slot == rootSlot, let next = list.active, next.slot != slot else { return }
      install(makeRoot(next.slot, relay.forward(next.slot)), slot: next.slot)
    }
  }

  private func reloadList() {
    list = registry.load() ?? list
  }

  private func install(_ newRoot: RootCoordinator, slot: AccountSlot) {
    let old = root
    root = newRoot
    rootSlot = slot
    AppDelegate.push = newRoot.push
    Task { await old.retire() }
  }
}

@MainActor
final class SessionRelay {
  weak var target: AccountsCoordinator?

  nonisolated func forward(_ slot: AccountSlot) -> @Sendable (SessionChange) -> Void {
    { change in
      Task { @MainActor in await self.target?.sessionChanged(change, in: slot) }
    }
  }
}

struct AccountsView: View {
  let accounts: AccountsCoordinator

  var body: some View {
    RootView(coordinator: accounts.root)
      .id(ObjectIdentifier(accounts.root))
      .environment(accounts)
      .sheet(isPresented: isAdding) {
        if let adding = accounts.adding {
          RootView(coordinator: adding)
            .overlay(alignment: .topTrailing) {
              Button("Cancel") { Task { await accounts.cancelAddingAccount() } }
                .padding()
            }
        }
      }
      .alert("Account not added", isPresented: hasNotice) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(accounts.notice?.message ?? "")
      }
  }

  private var isAdding: Binding<Bool> {
    Binding(
      get: { accounts.adding != nil },
      set: { if !$0 { Task { await accounts.cancelAddingAccount() } } })
  }

  private var hasNotice: Binding<Bool> {
    Binding(get: { accounts.notice != nil }, set: { if !$0 { accounts.notice = nil } })
  }
}

struct AccountSwitcherMenu: View {
  @Environment(AccountsCoordinator.self) private var accounts: AccountsCoordinator?

  var body: some View {
    if let accounts {
      Menu {
        ForEach(accounts.list.accounts) { account in
          Button {
            accounts.switchTo(userId: account.userId)
          } label: {
            if account.userId == accounts.activeUserId {
              Label(account.userId, systemImage: "checkmark")
            } else {
              Text(account.userId)
            }
          }
        }
        Divider()
        Button {
          accounts.startAddingAccount()
        } label: {
          Label("Add account", systemImage: "person.badge.plus")
        }
        .disabled(!accounts.canAddAccount)
      } label: {
        Image(systemName: "person.crop.circle")
      }
      .accessibilityLabel("Accounts")
    }
  }
}
