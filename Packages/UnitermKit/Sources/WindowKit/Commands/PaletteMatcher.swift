import Foundation

/// How well a query matches a piece of text. A higher score is a better match.
struct PaletteMatch: Equatable, Comparable {
  var score: Int

  static func < (lhs: PaletteMatch, rhs: PaletteMatch) -> Bool {
    lhs.score < rhs.score
  }
}

/// Fuzzy subsequence matching. Every character of the query must appear in the text in order,
/// ignoring case. The score rewards what a reader would call a good match: a prefix, a contiguous
/// run, and characters that start a word. It charges for the characters skipped between matches.
///
/// The constants are tuned so a contiguous prefix always beats a scattered match of the same
/// query. The scores are only meaningful against each other.
enum PaletteMatcher {
  static let perCharacter = 16
  static let consecutive = 12
  static let wordStart = 10
  static let firstCharacter = 8
  static let gapPenalty = 1
  static let maximumGapPenalty = 24
  static let contiguous = 40
  static let prefix = 40

  /// Returns nil when the query is not a subsequence of the text. An empty query matches
  /// everything with a score of zero.
  static func match(query: String, in text: String) -> PaletteMatch? {
    let needle = Array(query.lowercased())
    let haystack = Array(text.lowercased())

    guard !needle.isEmpty else { return PaletteMatch(score: 0) }

    guard needle.count <= haystack.count else { return nil }

    var best: Int?

    for start in haystack.indices where haystack[start] == needle[0] {
      if let score = score(needle, in: haystack, from: start) {
        best = max(best ?? score, score)
      }
    }

    guard var total = best else { return nil }

    let joined = String(haystack)
    let query = String(needle)

    if joined.hasPrefix(query) {
      total += prefix
    }

    if joined.contains(query) {
      total += contiguous
    }

    return PaletteMatch(score: total)
  }

  /// Scores the leftmost alignment that begins at `start`.
  private static func score(_ needle: [Character], in haystack: [Character], from start: Int)
    -> Int?
  {
    var total = 0
    var position = start
    var previous: Int?
    var skipped = 0

    for character in needle {
      while position < haystack.count, haystack[position] != character {
        position += 1
      }

      guard position < haystack.count else { return nil }

      total += perCharacter

      if position == 0 {
        total += firstCharacter
      }

      if let previous {
        if position == previous + 1 {
          total += consecutive
        } else {
          skipped += position - previous - 1
        }
      }

      if position > 0, isBoundary(haystack[position - 1]) {
        total += wordStart
      }

      previous = position
      position += 1
    }

    return total - min(skipped * gapPenalty, maximumGapPenalty)
  }

  private static func isBoundary(_ character: Character) -> Bool {
    character == " " || character == "-" || character == "_" || character == "/"
      || character == "."
  }
}
