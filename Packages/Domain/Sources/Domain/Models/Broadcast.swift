import Foundation

/// A new Broadcast, as the web's « New Broadcast » makes it: a room typed `app.twake.chat.page` where only moderators
/// and administrators post, followed in one of three ways chosen at creation.
public struct BroadcastDraft: Sendable, Equatable {
  /// How people follow the Broadcast. It cannot be changed afterwards.
  public enum Access: String, Sendable, Equatable, CaseIterable {
    /// Anyone joins; it is in the server's directory, its history is readable by anyone, and it has an address.
    case open
    /// Only people invited follow it; it is not in the directory.
    case invitation
    /// It is in the directory; people ask to follow (knock) and the administrators approve.
    case approval
  }

  /// The `m.room.create` type of a Broadcast.
  public static let roomType = "app.twake.chat.page"

  public var name: String
  public var topic: String
  public var access: Access
  /// The address of an open Broadcast, without `#` or server: lowercase letters, digits and dashes.
  public var slug: String
  /// Followers may react to posts.
  public var allowsReactions: Bool

  public init(
    name: String = "", topic: String = "", access: Access = .open, slug: String = "",
    allowsReactions: Bool = true
  ) {
    self.name = name
    self.topic = topic
    self.access = access
    self.slug = slug
    self.allowsReactions = allowsReactions
  }

  /// The address a name gives: lowercase, accents dropped, every run of other characters one dash.
  public static func slug(from name: String) -> String {
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .lowercased()
    var slug = ""
    for character in folded {
      if character.isASCII, character.isLetter || character.isNumber {
        slug.append(character)
      } else if !slug.isEmpty, slug.last != "-" {
        slug.append("-")
      }
    }
    while slug.last == "-" { slug.removeLast() }
    return slug
  }

  /// Whether `slug` is a valid address: lowercase letters, digits and dashes, not starting or ending with a dash.
  public static func isValidSlug(_ slug: String) -> Bool {
    !slug.isEmpty && slug.first != "-" && slug.last != "-"
      && slug.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
  }

  /// A name, and for an open Broadcast a valid address.
  public var canCreate: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (access != .open || Self.isValidSlug(slug))
  }
}
