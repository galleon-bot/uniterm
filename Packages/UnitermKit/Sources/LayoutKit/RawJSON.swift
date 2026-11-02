import Foundation

/// A JSON value held as the bytes it came from.
///
/// A layout file keeps each applet description verbatim, so a build that cannot read one writes it
/// back unchanged. A parsed value would lose key order, spacing, and numbers that a double cannot
/// hold. This type splits a document into the byte ranges of its members and elements instead.
///
/// The scanner assumes the document is valid JSON. `LayoutCodec` checks that first with the system
/// parser. A malformed document still never traps here, it throws.
public struct RawJSON: Sendable, Equatable {
  public let bytes: Data

  public init(_ bytes: Data) {
    self.bytes = bytes
  }

  public enum ScanError: Error, Equatable {
    case notAnObject
    case notAnArray
    case malformed
  }

  /// The members of an object, in file order. A repeated key appears once for each time.
  public func members() throws -> [(key: String, value: RawJSON)] {
    var scanner = Scanner(bytes: [UInt8](bytes))
    scanner.skipSpace()

    guard scanner.peek == UInt8(ascii: "{") else { throw ScanError.notAnObject }

    scanner.advance()
    scanner.skipSpace()

    var result: [(String, RawJSON)] = []

    if scanner.peek == UInt8(ascii: "}") { return result }

    while true {
      scanner.skipSpace()

      let keyRange = try scanner.skipValue()
      let keyBytes = Data(scanner.bytes[keyRange])

      guard keyBytes.first == UInt8(ascii: "\""),
        let key = try? JSONSerialization.jsonObject(with: keyBytes, options: [.fragmentsAllowed])
          as? String
      else { throw ScanError.malformed }

      scanner.skipSpace()
      try scanner.expect(UInt8(ascii: ":"))
      scanner.skipSpace()

      let valueRange = try scanner.skipValue()
      result.append((key, RawJSON(Data(scanner.bytes[valueRange]))))

      scanner.skipSpace()

      if scanner.peek == UInt8(ascii: ",") {
        scanner.advance()
        continue
      }

      try scanner.expect(UInt8(ascii: "}"))
      return result
    }
  }

  /// The elements of an array, in file order.
  public func elements() throws -> [RawJSON] {
    var scanner = Scanner(bytes: [UInt8](bytes))
    scanner.skipSpace()

    guard scanner.peek == UInt8(ascii: "[") else { throw ScanError.notAnArray }

    scanner.advance()
    scanner.skipSpace()

    var result: [RawJSON] = []

    if scanner.peek == UInt8(ascii: "]") { return result }

    while true {
      scanner.skipSpace()

      let range = try scanner.skipValue()
      result.append(RawJSON(Data(scanner.bytes[range])))

      scanner.skipSpace()

      if scanner.peek == UInt8(ascii: ",") {
        scanner.advance()
        continue
      }

      try scanner.expect(UInt8(ascii: "]"))
      return result
    }
  }

  /// The value of the last member with this key, as JSON does for a repeated key.
  public func member(_ key: String) throws -> RawJSON? {
    try members().last { $0.key == key }?.value
  }

  public var text: String? {
    guard bytes.first(where: { !Self.isSpace($0) }) == UInt8(ascii: "\"") else { return nil }

    return (try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])) as? String
  }

  /// The value when it is a plain non-negative integer literal.
  public var unsignedInteger: UInt64? {
    UInt64(trimmedText)
  }

  /// The value when it is an integer literal, which may be negative.
  public var integer: Int? {
    Int(trimmedText)
  }

  /// The value when it is a number.
  public var number: Double? {
    guard let value = Double(trimmedText), value.isFinite else { return nil }

    return value
  }

  private var trimmedText: String {
    String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isSpace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
  }

  private struct Scanner {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
      self.bytes = bytes
    }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func advance() {
      index += 1
    }

    mutating func skipSpace() {
      while index < bytes.count, RawJSON.isSpace(bytes[index]) { index += 1 }
    }

    mutating func expect(_ byte: UInt8) throws {
      guard peek == byte else { throw ScanError.malformed }

      advance()
    }

    /// Moves past one value and returns its byte range.
    mutating func skipValue() throws -> Range<Int> {
      skipSpace()

      let start = index

      guard let first = peek else { throw ScanError.malformed }

      switch first {
      case UInt8(ascii: "\""):
        try skipString()

      case UInt8(ascii: "{"), UInt8(ascii: "["):
        try skipContainer()

      default:
        while let byte = peek, byte != UInt8(ascii: ","), byte != UInt8(ascii: "}"),
          byte != UInt8(ascii: "]"), !RawJSON.isSpace(byte)
        {
          advance()
        }

        guard index > start else { throw ScanError.malformed }
      }

      return start..<index
    }

    private mutating func skipString() throws {
      advance()

      while let byte = peek {
        advance()

        if byte == UInt8(ascii: "\\") {
          guard peek != nil else { throw ScanError.malformed }

          advance()
        } else if byte == UInt8(ascii: "\"") {
          return
        }
      }

      throw ScanError.malformed
    }

    private mutating func skipContainer() throws {
      var depth = 0

      while let byte = peek {
        switch byte {
        case UInt8(ascii: "\""):
          try skipString()
          continue

        case UInt8(ascii: "{"), UInt8(ascii: "["):
          depth += 1

        case UInt8(ascii: "}"), UInt8(ascii: "]"):
          depth -= 1

        default:
          break
        }

        advance()

        if depth == 0 { return }
      }

      throw ScanError.malformed
    }
  }
}
