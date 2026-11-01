import Foundation

/// Why a command line cannot become a program and its arguments.
public enum ShellWordsError: Error, Equatable, LocalizedError {
  case empty
  case unterminatedQuote(Character)
  case danglingEscape
  case multipleLines
  case nulCharacter
  case shellSyntax(Character)

  public var errorDescription: String? {
    switch self {
    case .nulCharacter:
      return "The command holds a NUL character."

    case .empty:
      return "The command is empty."

    case .unterminatedQuote(let quote):
      return "The command has an opening \(quote) with no closing \(quote)."

    case .danglingEscape:
      return "The command ends with a backslash."

    case .multipleLines:
      return "The command must be one line."

    case .shellSyntax(let character):
      return
        "Program mode runs one program and does not read shell syntax, so \(character) must be quoted. To use pipes, variables, or globs, run sh -c with the script in quotes."
    }
  }
}

/// Splits a command line into words, the way a shell does for quotes and backslashes, and does
/// nothing else.
///
/// Program mode never hands the user's line to a shell. Single quotes keep every character. In double
/// quotes a backslash escapes `"`, `\`, `$`, and a backtick, and every other character stays.
/// Outside quotes, a backslash keeps the next character as it is.
///
/// Syntax that a shell would act on is refused unless it is quoted or escaped. That covers pipes,
/// redirects, globs, and a leading `~` outside quotes. It also covers `$` and a backtick, which a
/// shell expands even inside double quotes. Taking such a character literally would run something
/// other than what the user typed.
public enum ShellWords {
  private static let reserved: Set<Character> = [
    "|", "&", ";", "<", ">", "(", ")", "$", "`", "*", "?", "[", "]", "{", "}",
  ]

  public static func split(_ line: String) throws -> [String] {
    var words: [String] = []
    var current = ""
    var inWord = false
    var characters = line.makeIterator()

    func finishWord() {
      if inWord {
        words.append(current)
        current = ""
        inWord = false
      }
    }

    while let character = characters.next() {
      switch character {
      case "\n", "\r", "\r\n":
        throw ShellWordsError.multipleLines

      case " ", "\t":
        finishWord()

      case "'":
        inWord = true

        var closed = false
        while let next = characters.next() {
          if next == "'" {
            closed = true
            break
          }

          if next.isNewline { throw ShellWordsError.multipleLines }

          current.append(next)
        }

        guard closed else { throw ShellWordsError.unterminatedQuote("'") }

      case "\"":
        inWord = true

        var closed = false
        while let next = characters.next() {
          if next == "\"" {
            closed = true
            break
          }

          if next.isNewline { throw ShellWordsError.multipleLines }

          if next == "$" || next == "`" { throw ShellWordsError.shellSyntax(next) }

          if next == "\\" {
            guard let escaped = characters.next() else {
              throw ShellWordsError.unterminatedQuote("\"")
            }

            if !["\"", "\\", "$", "`"].contains(escaped) { current.append("\\") }

            if escaped.isNewline { throw ShellWordsError.multipleLines }

            current.append(escaped)
          } else {
            current.append(next)
          }
        }

        guard closed else { throw ShellWordsError.unterminatedQuote("\"") }

      case "\\":
        guard let escaped = characters.next() else { throw ShellWordsError.danglingEscape }

        if escaped.isNewline { throw ShellWordsError.multipleLines }

        inWord = true
        current.append(escaped)

      case "#", "~":
        if !inWord { throw ShellWordsError.shellSyntax(character) }

        current.append(character)

      default:
        if reserved.contains(character) { throw ShellWordsError.shellSyntax(character) }

        inWord = true
        current.append(character)
      }
    }

    finishWord()

    guard let first = words.first, !first.isEmpty else { throw ShellWordsError.empty }

    guard !words.contains(where: { $0.unicodeScalars.contains("\0") }) else {
      throw ShellWordsError.nulCharacter
    }

    return words
  }

  /// Joins words into one string that a POSIX shell reads back as exactly those words. Every word
  /// is single-quoted, so nothing in it is special.
  static func quote(_ words: [String]) -> String {
    words.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
  }
}
