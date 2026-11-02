import Foundation

/// What a palette entry stands for. Choosing it acts on this, never on a row or an index, so a
/// list that re-sorts under the keyboard still acts on the entry that was highlighted.
enum PaletteEntryID: Hashable, Sendable {
  case command(CommandID)
}

/// One row of the palette.
struct PaletteEntry: Equatable, Sendable {
  enum Kind: Sendable, Equatable {
    case command

    /// The word the row shows, so a program-set title can never pass for a command.
    var label: String {
      switch self {
      case .command: "Command"
      }
    }
  }

  var id: PaletteEntryID
  var kind: Kind
  var title: String

  /// Extra text the query also searches, such as a working directory. A match in the title
  /// outranks a match only here.
  var detail: String?

  /// A row for something that cannot run now still shows, dimmed, and Enter ignores it.
  var isEnabled: Bool
}

/// An entry together with what ranking needs to know about it.
struct PaletteCandidate: Sendable {
  var entry: PaletteEntry

  /// 0 for the most recently used entry of its kind, nil for one with no recency.
  var recencyRank: Int?

  /// The entry's place in its natural order, such as tree order for tabs. It breaks ties among
  /// entries with no recency.
  var order: Int
}

/// Orders the palette's entries for a query.
///
/// Match quality comes first. A match in the title outranks any match found only in the detail.
/// Recency adds a bounded boost, so it breaks ties and nudges close scores but cannot lift a weak
/// match above a strong one. With no query, recently used entries come first, then the rest.
enum PaletteRanking {
  /// The title tier sits above the detail tier by more than any quality score can reach.
  static let titleTier = 100_000
  static let detailTier = 50_000

  /// The boost for the most recent entry, and how much each older rank loses.
  static let recencyBoost = 24
  static let recencyStep = 6

  static func rank(_ candidates: [PaletteCandidate], query: String) -> [PaletteEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else {
      return emptyQueryOrder(candidates)
    }

    var scored: [(candidate: PaletteCandidate, score: Int)] = []

    for candidate in candidates {
      if let match = PaletteMatcher.match(query: trimmed, in: candidate.entry.title) {
        scored.append((candidate, titleTier + match.score + boost(candidate)))
      } else if let detail = candidate.entry.detail,
        let match = PaletteMatcher.match(query: trimmed, in: detail)
      {
        scored.append((candidate, detailTier + match.score + boost(candidate)))
      }
    }

    return scored.sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score > rhs.score }

      return naturalOrder(lhs.candidate, rhs.candidate)
    }.map(\.candidate.entry)
  }

  private static func boost(_ candidate: PaletteCandidate) -> Int {
    guard let rank = candidate.recencyRank else { return 0 }

    return max(0, recencyBoost - rank * recencyStep)
  }

  private static func emptyQueryOrder(_ candidates: [PaletteCandidate]) -> [PaletteEntry] {
    candidates.sorted(by: naturalOrder).map(\.entry)
  }

  /// Recent entries first, newest first. Then the rest in their natural order, with titles
  /// breaking a tie.
  private static func naturalOrder(_ lhs: PaletteCandidate, _ rhs: PaletteCandidate) -> Bool {
    switch (lhs.recencyRank, rhs.recencyRank) {
    case (let left?, let right?) where left != right:
      return left < right

    case (_?, nil):
      return true

    case (nil, _?):
      return false

    default:
      if lhs.order != rhs.order { return lhs.order < rhs.order }

      return lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
    }
  }
}

/// How a key binding behaves while the palette shows. The rules are pure so a test reads them
/// without a window.
enum PaletteDispatch: Equatable {
  /// The palette is not showing, so the binding runs as it always does.
  case run

  /// The palette hides and the binding runs nothing.
  case dismissOnly

  /// The palette hides and the binding runs on the pane that had focus before the palette.
  case dismissThenRun

  /// The palette's own toggle and Cmd-W only dismiss. Any other binding dismisses and then runs.
  /// Text-editing chords are not commands, so they never reach this decision.
  static func rule(for id: CommandID, paletteShown: Bool) -> PaletteDispatch {
    guard paletteShown else { return .run }

    switch id {
    case .showCommandPalette, .close: return .dismissOnly
    default: return .dismissThenRun
    }
  }
}
