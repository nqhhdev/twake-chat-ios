import Foundation
import MatrixRustSDK

/// One change to an ordered list, with the eleven cases of the SDK's `RoomListEntriesUpdate` (and `TimelineDiff`).
/// Generic so the applying logic is tested with plain values instead of SDK rooms.
enum ListDiff<Element> {
  case append([Element])
  case clear
  case pushFront(Element)
  case pushBack(Element)
  case popFront
  case popBack
  case insert(index: Int, Element)
  case set(index: Int, Element)
  case remove(index: Int)
  case truncate(length: Int)
  case reset([Element])

  /// Applies the change. The SDK sends indices that fit the list it describes; an index that does not fit (the list
  /// here would then be out of step) is ignored rather than crashing.
  func apply(to list: inout [Element]) {
    switch self {
    case .append(let values): list.append(contentsOf: values)
    case .clear: list.removeAll()
    case .pushFront(let value): list.insert(value, at: 0)
    case .pushBack(let value): list.append(value)
    case .popFront: if !list.isEmpty { list.removeFirst() }
    case .popBack: if !list.isEmpty { list.removeLast() }
    case .insert(let index, let value):
      if index >= 0, index <= list.count { list.insert(value, at: index) }
    case .set(let index, let value): if list.indices.contains(index) { list[index] = value }
    case .remove(let index): if list.indices.contains(index) { list.remove(at: index) }
    case .truncate(let length):
      if length >= 0, length < list.count { list.removeLast(list.count - length) }
    case .reset(let values): list = values
    }
  }

  /// The same change with each carried element transformed, in order.
  func map<T>(_ transform: (Element) async -> T) async -> ListDiff<T> {
    switch self {
    case .append(let values):
      var mapped: [T] = []
      for value in values { mapped.append(await transform(value)) }
      return .append(mapped)
    case .clear: return .clear
    case .pushFront(let value): return .pushFront(await transform(value))
    case .pushBack(let value): return .pushBack(await transform(value))
    case .popFront: return .popFront
    case .popBack: return .popBack
    case .insert(let index, let value): return .insert(index: index, await transform(value))
    case .set(let index, let value): return .set(index: index, await transform(value))
    case .remove(let index): return .remove(index: index)
    case .truncate(let length): return .truncate(length: length)
    case .reset(let values):
      var mapped: [T] = []
      for value in values { mapped.append(await transform(value)) }
      return .reset(mapped)
    }
  }
}

extension ListDiff where Element == Room {
  /// The SDK room list update as a `ListDiff`.
  init(_ update: RoomListEntriesUpdate) {
    switch update {
    case .append(let values): self = .append(values)
    case .clear: self = .clear
    case .pushFront(let value): self = .pushFront(value)
    case .pushBack(let value): self = .pushBack(value)
    case .popFront: self = .popFront
    case .popBack: self = .popBack
    case .insert(let index, let value): self = .insert(index: Int(index), value)
    case .set(let index, let value): self = .set(index: Int(index), value)
    case .remove(let index): self = .remove(index: Int(index))
    case .truncate(let length): self = .truncate(length: Int(length))
    case .reset(let values): self = .reset(values)
    }
  }
}
