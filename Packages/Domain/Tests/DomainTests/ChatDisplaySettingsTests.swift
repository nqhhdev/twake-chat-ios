import Domain
import Foundation
import Testing

@Suite struct ChatDisplaySettingsTests {
  private let day = Date(timeIntervalSince1970: 1_700_000_000)

  private func notice(_ id: String, _ visibility: TimelineItem.Visibility) -> TimelineItem {
    TimelineItem(id: id, kind: .stateNotice(id), visibility: visibility)
  }

  @Test func byDefaultBothKindsAreHidden() {
    let settings = ChatDisplaySettings()
    #expect(settings.shows(notice("joined", .always)))
    #expect(!settings.shows(notice("topic", .unimportant)))
    #expect(!settings.shows(notice("custom", .unknown)))
  }

  @Test func eachSwitchShowsItsKind() {
    let unimportant = ChatDisplaySettings(hidesUnimportantEvents: false)
    #expect(unimportant.shows(notice("topic", .unimportant)))
    #expect(!unimportant.shows(notice("custom", .unknown)))
    let unknown = ChatDisplaySettings(hidesUnknownEvents: false)
    #expect(!unknown.shows(notice("topic", .unimportant)))
    #expect(unknown.shows(notice("custom", .unknown)))
  }

  @Test func aDayLeftEmptyLosesItsDivider() {
    let items = [
      TimelineItem(id: "d1", kind: .dayDivider(day)),
      notice("topic", .unimportant),
      TimelineItem(id: "d2", kind: .dayDivider(day.addingTimeInterval(86_400))),
      notice("joined", .always),
      TimelineItem(id: "d3", kind: .dayDivider(day.addingTimeInterval(2 * 86_400))),
      TimelineItem(id: "marker", kind: .readMarker),
      notice("custom", .unknown),
    ]
    #expect(ChatDisplaySettings().visible(items).map(\.id) == ["d2", "joined", "marker"])
  }

  @Test func nothingHiddenKeepsTheListAsItIs() {
    let items = [TimelineItem(id: "d1", kind: .dayDivider(day)), notice("joined", .always)]
    #expect(ChatDisplaySettings().visible(items) == items)
  }
}
