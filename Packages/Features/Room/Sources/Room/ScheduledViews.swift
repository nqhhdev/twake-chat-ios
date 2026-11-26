import DesignSystem
import Domain
import SwiftUI

struct ScheduleSheet: View {
  let viewModel: RoomViewModel
  @State private var date = ScheduleSheet.defaultDate()
  @State private var isScheduling = false
  @Environment(\.dismiss) private var dismiss

  static func defaultDate(now: Date = .now) -> Date {
    let hour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
    let minutes = Calendar.current.component(.minute, from: hour)
    return Calendar.current.date(byAdding: .minute, value: -minutes, to: hour) ?? hour
  }

  var body: some View {
    NavigationStack {
      Form {
        DatePicker(
          localized("Send at"), selection: $date, in: Date.now.addingTimeInterval(60)...,
          displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.graphical)
        Section {
          Text(localized("The server sends it at this time, even with the app closed."))
            .font(.footnote)
            .foregroundStyle(SysColors.textSecondary)
        }
      }
      .navigationTitle(localized("Schedule Message"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(localized("Schedule")) {
            isScheduling = true
            Task {
              if await viewModel.schedule(at: date) { dismiss() }
              isScheduling = false
            }
          }
          .disabled(isScheduling)
        }
      }
    }
    .presentationDetents([.large])
  }
}

struct ScheduledBanner: View {
  let viewModel: RoomViewModel
  @State private var isListShown = false

  var body: some View {
    Button {
      isListShown = true
    } label: {
      Label(
        localized("\(viewModel.scheduled.count) scheduled messages"),
        systemImage: "clock"
      )
      .textStyle(TextStyles.labelLarge)
      .foregroundStyle(SysColors.primary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(SysColors.surface)
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $isListShown) { ScheduledListSheet(viewModel: viewModel) }
  }
}

struct ScheduledListSheet: View {
  let viewModel: RoomViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(viewModel.scheduled) { message in
          VStack(alignment: .leading, spacing: 4) {
            Text(message.sendAt, format: .dateTime.weekday().day().month().hour().minute())
              .font(.footnote.weight(.semibold))
              .foregroundStyle(SysColors.primary)
            Text(message.text).lineLimit(4)
          }
          .swipeActions {
            Button(localized("Cancel"), systemImage: "trash", role: .destructive) {
              Task { await viewModel.cancelScheduled(message) }
            }
          }
          .contextMenu {
            Button(localized("Send Now"), systemImage: "paperplane") {
              Task { await viewModel.sendScheduledNow(message) }
            }
            Button(localized("Edit"), systemImage: "pencil") {
              dismiss()
              Task { await viewModel.editScheduled(message) }
            }
            Button(localized("Cancel Message"), systemImage: "trash", role: .destructive) {
              Task { await viewModel.cancelScheduled(message) }
            }
          }
        }
      }
      .overlay {
        if viewModel.scheduled.isEmpty {
          ContentUnavailableView(localized("No scheduled messages"), systemImage: "clock")
        }
      }
      .navigationTitle(localized("Scheduled"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(localized("Done")) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
