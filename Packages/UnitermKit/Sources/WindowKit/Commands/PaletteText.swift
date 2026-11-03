import Foundation

/// Makes text from a program safe to show in a palette row.
///
/// A program sets a tab's title, and a shell reports its directory, so both are untrusted. A
/// title with a newline could pose as a second row. A title with a right-to-left override could
/// reorder what follows it, so a tab could read as a command. Control characters, line breaks, and
/// spaces of any width become one space. The bidirectional controls and other invisible format
/// characters are dropped, except a joiner inside an emoji sequence. The cap counts unicode scalars,
/// since one letter with thousands of combining marks is a single character.
enum PaletteText {
  /// Longest text a row shows or the matcher reads, in unicode scalars.
  static let maximumLength = 120

  static func neutralized(_ text: String) -> String {
    var scalars: [Unicode.Scalar] = []

    for scalar in text.unicodeScalars {
      if isBidirectionalControl(scalar) { continue }

      if isBreak(scalar) {
        if let last = scalars.last, last != " " { scalars.append(" ") }

        continue
      }

      if scalar.properties.generalCategory == .format {
        // A joiner holds an emoji sequence together. Anywhere else it draws nothing.
        guard scalar.value == 0x200D, let last = scalars.last, last != " ", last.value != 0x200D
        else { continue }
      }

      scalars.append(scalar)
    }

    while let last = scalars.last, last == " " || last.value == 0x200D {
      scalars.removeLast()
    }

    var result = ""
    result.unicodeScalars.append(contentsOf: scalars.prefix(maximumLength))
    return result
  }

  /// The Arabic letter mark, the left and right marks, the embeddings and overrides, and the
  /// isolates.
  private static func isBidirectionalControl(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true
    default: return false
    }
  }

  private static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .lineSeparator, .paragraphSeparator, .spaceSeparator: return true
    default: return scalar == " "
    }
  }
}
