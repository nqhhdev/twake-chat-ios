import DesignSystem
import Domain
import SwiftUI

extension RoomMember.Role {
  /// The label beside a member's name; a plain member has none.
  var label: String? {
    switch self {
    case .creator: localized("Owner")
    case .administrator: localized("Admin")
    case .moderator: localized("Moderator")
    case .user: nil
    }
  }
}

/// A member's profile (Flutter `profile_info`), laid out as an iOS contact card: the picture and name, quick actions
/// (Message, Copy ID), the Matrix ID, then Remove from chat and Block, each confirmed first.
struct MemberProfileScreen: View {
  /// The member as opened; `member` reads them as the details show them now, after a role change.
  let opened: RoomMember
  let viewModel: RoomDetailsViewModel
  @State private var isConfirmingBan = false

  init(member: RoomMember, viewModel: RoomDetailsViewModel) {
    self.opened = member
    self.viewModel = viewModel
  }

  private var member: RoomMember { viewModel.members.first { $0.id == opened.id } ?? opened }
  @Environment(\.dismiss) private var dismiss
  @State private var isConfirmingRemove = false
  @State private var isConfirmingBlock = false
  @State private var isWorking = false
  @State private var copied = false
  @State private var common: [RoomInCommon]?
  @State private var status: String?

  var body: some View {
    List {
      Section {
        VStack(spacing: 10) {
          TwakeAvatar(
            name: member.name, size: 104, pictureID: member.avatar?.source,
            load: member.avatar.map { reference in
              { @Sendable [viewModel] in await viewModel.picture(reference) }
            })
          Text(member.name)
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
          if let role = member.role.label {
            Text(role)
              .font(.footnote.weight(.medium))
              .foregroundStyle(SysColors.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 3)
              .background(SysColors.primary.opacity(0.12), in: .capsule)
          }
          if member.membership == .invited {
            Text(localized("Invited")).font(.footnote).foregroundStyle(SysColors.textSecondary)
          }
          actions.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
      }
      if let status {
        Section(localized("Status")) {
          Label(status, systemImage: "quote.bubble")
            .transition(.opacity)
        }
      }
      Section {
        LabeledContent(localized("Matrix ID")) {
          Text(member.id).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
      }
      if let common, !common.isEmpty, !member.isOwn {
        Section(
          localized("\(common.count) groups in common")
        ) {
          ForEach(common) { room in
            Label {
              Text(room.name).lineLimit(1)
            } icon: {
              TwakeAvatar(name: room.name, size: 28)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
      }
      if !member.assignableRoles.isEmpty {
        Section {
          Picker(
            localized("Role"),
            selection: Binding(
              get: { member.role },
              set: { role in
                Task {
                  isWorking = true
                  defer { isWorking = false }
                  await viewModel.setRole(role, for: member)
                }
              })
          ) {
            ForEach(member.assignableRoles, id: \.self) { role in
              Text(role.label ?? localized("Member")).tag(role)
            }
          }
          .disabled(isWorking)
        } footer: {
          Text(
            localized(
              "Admins can change the chat and people's roles; moderators can remove and ban members."
            ))
        }
      }
      if member.canBeRemoved || member.canBeBanned || viewModel.canBlock(member) {
        Section {
          if member.canBeRemoved {
            Button(
              localized("Remove from chat"), systemImage: "person.badge.minus", role: .destructive
            ) {
              isConfirmingRemove = true
            }
          }
          if member.canBeBanned {
            Button(localized("Ban from chat"), systemImage: "nosign", role: .destructive) {
              isConfirmingBan = true
            }
          }
          if viewModel.canBlock(member) {
            Button(localized("Block"), systemImage: "hand.raised", role: .destructive) {
              isConfirmingBlock = true
            }
          }
        }
        .disabled(isWorking)
      }
      if let message = viewModel.errorMessage {
        Text(message).foregroundStyle(SysColors.error)
      }
    }
    .navigationTitle(member.name)
    .navigationBarTitleDisplayMode(.inline)
    .sensoryFeedback(.success, trigger: copied)
    .task(id: member.id) {
      async let message = viewModel.statusMessage(of: member.id)
      let found = await viewModel.roomsInCommon(with: member.id)
      let statusText = await message
      withAnimation(.easeInOut) { status = statusText }
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { common = found }
    }
    .confirmationDialog(
      localized("Ban \(member.name) from this chat?"), isPresented: $isConfirmingBan,
      titleVisibility: .visible
    ) {
      Button(localized("Ban"), role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          if await viewModel.ban(member) { dismiss() }
        }
      }
    } message: {
      Text(localized("They are removed and cannot join again until they are unbanned in Banned."))
    }
    .confirmationDialog(
      localized("Remove \(member.name) from this chat?"), isPresented: $isConfirmingRemove,
      titleVisibility: .visible
    ) {
      Button(localized("Remove"), role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          if await viewModel.remove(member) { dismiss() }
        }
      }
    } message: {
      Text(localized("They can join again only if someone invites them."))
    }
    .confirmationDialog(
      localized("Block \(member.name)?"), isPresented: $isConfirmingBlock, titleVisibility: .visible
    ) {
      Button(localized("Block"), role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          if await viewModel.block(member) { dismiss() }
        }
      }
    } message: {
      Text(
        localized(
          "You will no longer see their messages, in any chat. You can unblock them in Settings."))
    }
  }

  /// The contact card's round-cornered action buttons.
  private var actions: some View {
    HStack(spacing: 10) {
      if viewModel.openDirectChat != nil, !member.isOwn {
        ProfileAction(title: "Message", systemImage: "message.fill") {
          Task {
            isWorking = true
            defer { isWorking = false }
            await viewModel.message(member)
          }
        }
        .disabled(isWorking)
      }
      ProfileAction(title: copied ? localized("Copied") : "Copy ID", systemImage: "doc.on.doc.fill")
      {
        UIPasteboard.general.string = member.id
        copied = true
        Task {
          try? await Task.sleep(for: .seconds(1.5))
          copied = false
        }
      }
    }
    .frame(maxWidth: 360)
  }
}

/// One action of a contact card: an icon over a short title in a rounded tile.
private struct ProfileAction: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: systemImage).font(.system(size: 18)).frame(height: 24)
        Text(title).font(.caption.weight(.medium))
      }
      .frame(maxWidth: .infinity, minHeight: 56)
      .foregroundStyle(SysColors.primary)
      .background(SysColors.surface, in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}
