import DesignSystem
import Domain
import SwiftUI

extension RoomMember.Role {
  /// The label beside a member's name; a plain member has none.
  var label: String? {
    switch self {
    case .creator: "Owner"
    case .administrator: "Admin"
    case .moderator: "Moderator"
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
            Text("Invited").font(.footnote).foregroundStyle(SysColors.textSecondary)
          }
          actions.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
      }
      Section {
        LabeledContent("Matrix ID") {
          Text(member.id).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
      }
      if !member.assignableRoles.isEmpty {
        Section {
          Picker(
            "Role",
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
              Text(role.label ?? "Member").tag(role)
            }
          }
          .disabled(isWorking)
        } footer: {
          Text(
            "Admins can change the chat and people's roles; moderators can remove and ban members.")
        }
      }
      if member.canBeRemoved || member.canBeBanned || viewModel.canBlock(member) {
        Section {
          if member.canBeRemoved {
            Button("Remove from chat", systemImage: "person.badge.minus", role: .destructive) {
              isConfirmingRemove = true
            }
          }
          if member.canBeBanned {
            Button("Ban from chat", systemImage: "nosign", role: .destructive) {
              isConfirmingBan = true
            }
          }
          if viewModel.canBlock(member) {
            Button("Block", systemImage: "hand.raised", role: .destructive) {
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
    .confirmationDialog(
      "Ban \(member.name) from this chat?", isPresented: $isConfirmingBan, titleVisibility: .visible
    ) {
      Button("Ban", role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          if await viewModel.ban(member) { dismiss() }
        }
      }
    } message: {
      Text("They are removed and cannot join again until they are unbanned in Banned.")
    }
    .confirmationDialog(
      "Remove \(member.name) from this chat?", isPresented: $isConfirmingRemove,
      titleVisibility: .visible
    ) {
      Button("Remove", role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          if await viewModel.remove(member) { dismiss() }
        }
      }
    } message: {
      Text("They can join again only if someone invites them.")
    }
    .confirmationDialog(
      "Block \(member.name)?", isPresented: $isConfirmingBlock, titleVisibility: .visible
    ) {
      Button("Block", role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          if await viewModel.block(member) { dismiss() }
        }
      }
    } message: {
      Text("You will no longer see their messages, in any chat. You can unblock them in Settings.")
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
      ProfileAction(title: copied ? "Copied" : "Copy ID", systemImage: "doc.on.doc.fill") {
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
