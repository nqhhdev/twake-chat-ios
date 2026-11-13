import Testing

@testable import MatrixData

/// The room list diff applier with plain fixture arrays, one test per `RoomListEntriesUpdate` case.
struct ListDiffTests {
  private func applying(_ diffs: [ListDiff<String>], to start: [String]) -> [String] {
    var list = start
    for diff in diffs { diff.apply(to: &list) }
    return list
  }

  @Test func append() {
    #expect(applying([.append(["c", "d"])], to: ["a", "b"]) == ["a", "b", "c", "d"])
  }
  @Test func clear() { #expect(applying([.clear], to: ["a", "b"]) == []) }
  @Test func pushFront() {
    #expect(applying([.pushFront("z")], to: ["a", "b"]) == ["z", "a", "b"])
  }
  @Test func pushBack() { #expect(applying([.pushBack("z")], to: ["a", "b"]) == ["a", "b", "z"]) }
  @Test func popFront() { #expect(applying([.popFront], to: ["a", "b"]) == ["b"]) }
  @Test func popBack() { #expect(applying([.popBack], to: ["a", "b"]) == ["a"]) }
  @Test func insert() {
    #expect(applying([.insert(index: 1, "z")], to: ["a", "b"]) == ["a", "z", "b"])
    #expect(applying([.insert(index: 2, "z")], to: ["a", "b"]) == ["a", "b", "z"])
  }
  @Test func set() {
    #expect(applying([.set(index: 1, "z")], to: ["a", "b", "c"]) == ["a", "z", "c"])
  }
  @Test func remove() {
    #expect(applying([.remove(index: 0)], to: ["a", "b", "c"]) == ["b", "c"])
  }
  @Test func truncate() { #expect(applying([.truncate(length: 1)], to: ["a", "b", "c"]) == ["a"]) }
  @Test func reset() {
    #expect(applying([.reset(["x", "y"])], to: ["a", "b", "c"]) == ["x", "y"])
  }

  /// A room moving to the top after a new message arrives as a remove then an insert at 0.
  @Test func aSequenceOfUpdates() {
    let diffs: [ListDiff<String>] = [
      .reset(["a", "b", "c"]), .remove(index: 2), .insert(index: 0, "c*"), .set(index: 1, "a*"),
      .pushBack("d"), .popFront,
    ]
    #expect(applying(diffs, to: []) == ["a*", "b", "d"])
  }

  @Test func indicesOutsideTheListAreIgnored() {
    let diffs: [ListDiff<String>] = [
      .insert(index: 5, "z"), .set(index: 3, "z"), .remove(index: 2), .truncate(length: 4),
    ]
    #expect(applying(diffs, to: ["a", "b"]) == ["a", "b"])
    #expect(applying([.popFront, .popBack], to: []) == [])
  }

  // MARK: Tester (TWAK-66): the list's edges, which the first page and an emptied list reach.

  /// The first update on an empty list, and updates that empty it or reach its ends.
  @Test func updatesAtTheEdgesOfTheList() {
    #expect(applying([.insert(index: 0, "a")], to: []) == ["a"])
    #expect(applying([.pushFront("a")], to: []) == ["a"])
    #expect(applying([.append([])], to: ["a"]) == ["a"])
    #expect(applying([.clear], to: []) == [])
    #expect(applying([.reset([])], to: ["a", "b"]) == [])
    #expect(applying([.truncate(length: 0)], to: ["a", "b"]) == [])
    #expect(applying([.truncate(length: 2)], to: ["a", "b"]) == ["a", "b"])
    #expect(applying([.remove(index: 0)], to: ["a"]) == [])
    #expect(applying([.set(index: 0, "z")], to: []) == [])
    #expect(applying([.insert(index: -1, "z"), .remove(index: -1), .set(index: -1, "z")], to: ["a"]) == ["a"])
  }

  @Test func mapTransformsOnlyTheCarriedElements() async {
    var list = ["A", "B"]
    let diff: ListDiff<Int> = .insert(index: 1, 7)
    await diff.map { "\($0)" }.apply(to: &list)
    #expect(list == ["A", "7", "B"])
    var reset: [String] = []
    await ListDiff<Int>.reset([1, 2]).map { "\($0)" }.apply(to: &reset)
    #expect(reset == ["1", "2"])
  }
}
