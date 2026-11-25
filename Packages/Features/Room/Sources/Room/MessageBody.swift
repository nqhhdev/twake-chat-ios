import DesignSystem
import Domain
import MapKit
import SwiftUI

/// The content of a message, by kind. A text, emote or notice shows as its sender formatted it when it has an HTML
/// body (bold, links, mentions, quotes, lists, code), as the web client draws it.
struct MessageBody: View {
  let content: TimelineMessage.Body
  var formatted: AttributedString?
  /// This device is verified, which decides the help under a message that cannot be decrypted.
  var isDeviceVerified = true
  /// The reader tapped the message: its spoilers show.
  @State private var revealsSpoilers = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The text with each spoiler covered by a solid block and its links turned off, until revealed.
  static func concealingSpoilers(_ text: AttributedString) -> AttributedString {
    var result = text
    for run in text.runs where run[SpoilerAttribute.self] == true {
      result[run.range].foregroundColor = .clear
      result[run.range].backgroundColor = Color.secondary.opacity(0.45)
      result[run.range].link = nil
    }
    return result
  }

  /// A formatted text, its spoilers covered until the reader taps it.
  @ViewBuilder private func rich(_ text: AttributedString) -> some View {
    if text.hasSpoiler {
      Text(revealsSpoilers ? text : Self.concealingSpoilers(text))
        .contentTransition(.opacity)
        .onTapGesture {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { revealsSpoilers.toggle() }
        }
        .accessibilityHint(revealsSpoilers ? "Hides the spoiler" : "Shows the spoiler")
        .accessibilityAddTraits(.isButton)
    } else {
      Text(text)
    }
  }

  /// A message without HTML: its inline Markdown (bold, italic, code, links) and bare addresses as links. The text is
  /// never looked up as a localisation key.
  static func plain(_ text: String) -> AttributedString {
    let parsed =
      (try? AttributedString(
        markdown: text,
        options: .init(
          allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
          failurePolicy: .returnPartiallyParsedIfPossible)))
      ?? AttributedString(text)
    return MatrixHTML.linkingBareAddresses(parsed)
  }

  /// An emote, as "* text" in italics.
  static func emote(_ text: AttributedString) -> AttributedString {
    var line = AttributedString("* ") + text
    for run in line.runs {
      line[run.range].inlinePresentationIntent =
        (run.inlinePresentationIntent ?? []).union(.emphasized)
    }
    return line
  }

  /// The text "Select Text" opens, formatted as the bubble shows it but with its spoilers uncovered; `nil` for a
  /// message without text of its own to select (media, a deleted or an undecryptable message), or an empty one.
  static func selectableText(of content: TimelineMessage.Body, formatted: AttributedString?)
    -> AttributedString?
  {
    let text: AttributedString
    switch content {
    case .text(let plain), .notice(let plain): text = formatted ?? Self.plain(plain)
    case .emote(let plain): text = Self.emote(formatted ?? Self.plain(plain))
    default: return nil
    }
    return String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? nil : text
  }

  var body: some View {
    Group {
      switch content {
      case .text(let text): rich(formatted ?? Self.plain(text))
      case .emote(let text): rich(Self.emote(formatted ?? Self.plain(text)))
      case .notice(let text):
        rich(formatted ?? Self.plain(text)).foregroundStyle(SysColors.textSecondary)
      case .image(let caption): Label(caption ?? "Picture", systemImage: "photo")
      case .video(let caption): Label(caption ?? "Video", systemImage: "video")
      case .audio(let caption): Label(caption ?? "Audio", systemImage: "waveform")
      case .file(let name): Label(name, systemImage: "doc")
      case .location(let text, let place):
        if let place {
          LocationCard(text: text, place: place)
        } else {
          Label(text, systemImage: "mappin.and.ellipse")
        }
      case .sticker(let text): Text(text)
      case .poll(let question): Label(question, systemImage: "chart.bar")
      case .redacted:
        Label("This message has been deleted", systemImage: "trash").foregroundStyle(
          SysColors.textSecondary)
      case .unableToDecrypt(let reason):
        // The web's wording: the line, then why the key is missing or what brings it back.
        VStack(alignment: .leading, spacing: 2) {
          Label("This message cannot be read on this device yet.", systemImage: "lock.badge.clock")
          Text(reason.help(isDeviceVerified: isDeviceVerified))
            .textStyle(TextStyles.labelSmall)
        }
        .foregroundStyle(SysColors.textSecondary)
      case .unsupported:
        Text("Unknown event").foregroundStyle(SysColors.textSecondary)
      }
    }
    .textStyle(TextStyleToken(size: 15, lineHeight: 20, weight: .regular, letterSpacing: 0))
    .foregroundStyle(SysColors.onSurface)
  }
}

/// A vertical stack as wide as its widest child at its natural size, but at most `maxWidth`; every child is then laid
/// out at that width, so text wraps at it and trailing parts (the time) line up on the right.
struct HuggingStack: Layout {
  let maxWidth: CGFloat
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = width(of: subviews)
    let heights = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }
    return CGSize(
      width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for subview in subviews {
      let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
      subview.place(
        at: CGPoint(x: bounds.minX, y: y),
        proposal: ProposedViewSize(width: bounds.width, height: height))
      y += height + spacing
    }
  }

  private func width(of subviews: Subviews) -> CGFloat {
    min(maxWidth, subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0)
  }
}

/// Lays its children out in rows, as wide as `maxWidth` allows, starting a new row when the next child does not fit;
/// each row hugs the leading or the trailing edge. Reactions use it, so many of them wrap under the bubble instead of
/// making the chat wider than the screen.
struct WrappingStack: Layout {
  var spacing: CGFloat = 4
  var alignsTrailing = false

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let rows = Self.rows(
      of: sizes.map(\.width), maxWidth: proposal.width ?? .infinity, spacing: spacing)
    let width = rows.map { rowWidth($0, sizes) }.max() ?? 0
    let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
    return CGSize(
      width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    var y = bounds.minY
    for row in Self.rows(of: sizes.map(\.width), maxWidth: bounds.width, spacing: spacing) {
      var x = alignsTrailing ? bounds.maxX - rowWidth(row, sizes) : bounds.minX
      for index in row {
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[index]))
        x += sizes[index].width + spacing
      }
      y += (row.map { sizes[$0].height }.max() ?? 0) + spacing
    }
  }

  private func rowWidth(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
    row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
  }

  /// The children of each row, by index: as many as fit in `maxWidth`, and at least one, so a child wider than the
  /// row still shows.
  static func rows(of widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
    var rows: [[Int]] = []
    var current: [Int] = []
    var used: CGFloat = 0
    for (index, width) in widths.enumerated() {
      let needed = current.isEmpty ? width : used + spacing + width
      if !current.isEmpty, needed > maxWidth {
        rows.append(current)
        current = [index]
        used = width
      } else {
        current.append(index)
        used = needed
      }
    }
    if !current.isEmpty { rows.append(current) }
    return rows
  }
}

/// The card under a message's first web link (Flutter `TwakeLinkPreview`): the page's picture, site, title and
/// description, as the homeserver previews it. It shows nothing until the preview arrives, or when there is none; a tap
/// opens the link.
struct LinkPreviewCard: View {
  let url: URL
  let width: CGFloat
  let viewModel: RoomViewModel
  @State private var preview: LinkPreview?
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      if let preview {
        Button {
          guard viewModel.focus == nil else { return }
          openURL(preview.url)
        } label: {
          card(preview)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      }
    }
    .task(id: url) {
      let loaded = await viewModel.linkPreview(of: url)
      withAnimation(.easeOut(duration: 0.2)) { preview = loaded }
    }
  }

  private func card(_ preview: LinkPreview) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let image = preview.image {
        let height = min(160, width * (image.aspectRatio ?? 0.52))
        RemoteImage(
          media: image, size: CGSize(width: width, height: height), repository: viewModel.media
        )
        .frame(width: width, height: height)
        .clipped()
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(preview.siteName ?? preview.url.host() ?? "")
          .font(.caption.weight(.medium))
          .foregroundStyle(SysColors.primary)
          .lineLimit(1)
        if let title = preview.title {
          Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        if let description = preview.description {
          Text(description).font(.footnote).foregroundStyle(SysColors.textSecondary).lineLimit(3)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
    }
    .frame(width: width, alignment: .leading)
    .background(SysColors.surface.opacity(0.7))
    .clipShape(.rect(cornerRadius: 10))
    .overlay(alignment: .leading) {
      Rectangle().fill(SysColors.primary).frame(width: 3)
        .clipShape(.rect(topLeadingRadius: 10, bottomLeadingRadius: 10))
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens the link")
  }
}

/// A location message: a still map with a pin, and the sender's text. A tap opens the place in Apple Maps.
private struct LocationCard: View {
  let text: String
  let place: GeoPoint
  @Environment(\.openURL) private var openURL

  private var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
  }

  var body: some View {
    Button {
      if let url = place.appleMapsURL { openURL(url) }
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Map(
          initialPosition: .region(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)),
          interactionModes: []
        ) {
          Marker("", coordinate: coordinate)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        Label(text, systemImage: "mappin.and.ellipse")
          .multilineTextAlignment(.leading)
        Text("Open in Maps")
          .textStyle(TextStyles.bodyMedium)
          .foregroundStyle(SysColors.textSecondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Location: \(text). Open in Maps")
  }
}
