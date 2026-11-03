import XCTest

@testable import WindowKit

/// The palette's matcher, ranking, and dispatch rules, apart from any view.
final class PaletteRankingTests: XCTestCase {
  private func entry(_ title: String, detail: String? = nil, enabled: Bool = true) -> PaletteEntry {
    PaletteEntry(
      id: .command(CommandID(title)), kind: .command, title: title, detail: detail,
      isEnabled: enabled)
  }

  private func candidates(_ titles: [String], recent: [String] = []) -> [PaletteCandidate] {
    titles.enumerated().map { order, title in
      PaletteCandidate(
        entry: entry(title), recencyRank: recent.firstIndex(of: title), order: order)
    }
  }

  private func titles(_ ranked: [PaletteEntry]) -> [String] {
    ranked.map(\.title)
  }

  /// Catches a matcher that requires a contiguous run, or one that ignores order.
  func testAMatchIsAnOrderedSubsequenceIgnoringCase() {
    XCTAssertNotNil(PaletteMatcher.match(query: "sPrt", in: "Split Right"))
    XCTAssertNil(PaletteMatcher.match(query: "trs", in: "Split Right"))
    XCTAssertNil(PaletteMatcher.match(query: "splitrightx", in: "Split Right"))
    XCTAssertEqual(PaletteMatcher.match(query: "", in: "Anything")?.score, 0)
  }

  /// Catches a prefix or contiguous match that a scattered match of the same letters can beat.
  func testAPrefixOutranksAScatteredMatchOfTheSameLetters() throws {
    let prefix = try XCTUnwrap(PaletteMatcher.match(query: "clo", in: "Close Tab or Pane"))
    let scattered = try XCTUnwrap(
      PaletteMatcher.match(query: "clo", in: "Focus Pane Left or Right"))

    XCTAssertGreaterThan(prefix, scattered)
  }

  /// Catches a ranking that lets a detail-only match beat a title match, which is the tab title
  /// versus working directory case.
  func testATitleMatchOutranksAMatchFoundOnlyInTheDetail() {
    let entries = [
      PaletteCandidate(entry: entry("Alpha", detail: "/src/build"), recencyRank: 0, order: 0),
      PaletteCandidate(entry: entry("Zebra build"), recencyRank: nil, order: 1),
    ]

    XCTAssertEqual(titles(PaletteRanking.rank(entries, query: "build")), ["Zebra build", "Alpha"])
  }

  /// Catches a recency boost with no bound. A recent weak match must not beat a strong one.
  func testRecencyCannotLiftAWeakMatchAboveAStrongOne() {
    let ranked = PaletteRanking.rank(
      candidates(["Select Previous Tab", "Split Right"], recent: ["Select Previous Tab"]),
      query: "split")

    XCTAssertEqual(titles(ranked).first, "Split Right")
  }

  /// Catches recency that does not break a tie between equal matches.
  func testRecencyBreaksATieBetweenEqualMatches() {
    let ranked = PaletteRanking.rank(
      candidates(["Split Down", "Split Right"], recent: ["Split Right"]), query: "split")

    XCTAssertEqual(titles(ranked), ["Split Right", "Split Down"])
  }

  /// Catches an empty query that hides what was run last. Recent commands lead, newest first,
  /// then the rest in their natural order.
  func testAnEmptyQueryListsRecentCommandsFirst() {
    let ranked = PaletteRanking.rank(
      candidates(["B", "A", "C", "D"], recent: ["C", "D"]), query: "  ")

    XCTAssertEqual(titles(ranked), ["C", "D", "B", "A"])
  }

  /// Catches a ranking that keeps entries the query does not match.
  func testNonMatchingEntriesAreDropped() {
    XCTAssertTrue(PaletteRanking.rank(candidates(["Split Right"]), query: "zzz").isEmpty)
  }

  /// Catches a toggle that does more than hide, and a Cmd-W that closes while the palette shows.
  func testDispatchRulesWhileThePaletteShows() {
    XCTAssertEqual(PaletteDispatch.rule(for: .splitRight, paletteShown: false), .run)
    XCTAssertEqual(PaletteDispatch.rule(for: .close, paletteShown: false), .run)
    XCTAssertEqual(PaletteDispatch.rule(for: .showCommandPalette, paletteShown: true), .dismissOnly)
    XCTAssertEqual(PaletteDispatch.rule(for: .close, paletteShown: true), .dismissOnly)
    XCTAssertEqual(PaletteDispatch.rule(for: .splitRight, paletteShown: true), .dismissThenRun)
    XCTAssertEqual(PaletteDispatch.rule(for: .quit, paletteShown: true), .dismissThenRun)
  }
}

/// The text rules for what a palette row shows.
final class PaletteTextTests: XCTestCase {
  /// Catches a bidi override or a line break that survives into a row. A title could otherwise
  /// reorder the text after it or forge a second row.
  func testControlAndBidiCharactersAreNeutralized() {
    XCTAssertEqual(PaletteText.neutralized("a\u{202E}b\u{2067}c\u{200F}d\u{061C}"), "abcd")
    XCTAssertEqual(
      PaletteText.neutralized("one\r\ntwo\u{2028}three\tfour\u{7}"), "one two three four")
    XCTAssertEqual(PaletteText.neutralized("  spaced   out  "), "spaced out")
    XCTAssertEqual(PaletteText.neutralized("\u{202E}\u{1B}"), "")
  }

  /// Catches a title long enough to push the kind label off the row.
  func testTextIsCapped() {
    XCTAssertEqual(
      PaletteText.neutralized(String(repeating: "x", count: 500)).count,
      PaletteText.maximumLength)
  }

  /// Catches emoji sequences that lose their joiner, since only bidi controls are dropped.
  func testEmojiJoinersSurvive() {
    XCTAssertEqual(PaletteText.neutralized("👩\u{200D}💻"), "👩\u{200D}💻")
  }
}
