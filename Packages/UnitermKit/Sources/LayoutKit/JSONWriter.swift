import Foundation

/// A JSON document built for writing. Objects keep their member order, so a saved file is the same
/// bytes for the same layout. A raw member is written exactly as given.
enum JSONOut {
  case raw(Data)
  case string(String)
  case integer(Int64)
  case unsigned(UInt64)
  case number(Double)
  case array([JSONOut])
  case object([(String, JSONOut)])

  func serialized() -> Data {
    var out = Data()
    write(into: &out)
    return out
  }

  private func write(into out: inout Data) {
    switch self {
    case .raw(let data):
      out.append(data)

    case .string(let text):
      Self.writeString(text, into: &out)

    case .integer(let value):
      out.append(contentsOf: String(value).utf8)

    case .unsigned(let value):
      out.append(contentsOf: String(value).utf8)

    case .number(let value):
      out.append(contentsOf: (value.isFinite ? "\(value)" : "0").utf8)

    case .array(let items):
      out.append(UInt8(ascii: "["))

      for (index, item) in items.enumerated() {
        if index > 0 { out.append(UInt8(ascii: ",")) }

        item.write(into: &out)
      }

      out.append(UInt8(ascii: "]"))

    case .object(let members):
      out.append(UInt8(ascii: "{"))

      for (index, member) in members.enumerated() {
        if index > 0 { out.append(UInt8(ascii: ",")) }

        Self.writeString(member.0, into: &out)
        out.append(UInt8(ascii: ":"))
        member.1.write(into: &out)
      }

      out.append(UInt8(ascii: "}"))
    }
  }

  private static func writeString(_ text: String, into out: inout Data) {
    out.append(UInt8(ascii: "\""))

    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out.append(contentsOf: Array("\\\"".utf8))
      case "\\": out.append(contentsOf: Array("\\\\".utf8))
      case "\n": out.append(contentsOf: Array("\\n".utf8))
      case "\r": out.append(contentsOf: Array("\\r".utf8))
      case "\t": out.append(contentsOf: Array("\\t".utf8))

      case _ where scalar.value < 0x20:
        let hex = String(scalar.value, radix: 16)
        out.append(
          contentsOf: Array("\\u\(String(repeating: "0", count: 4 - hex.count))\(hex)".utf8))

      default:
        out.append(contentsOf: Array(String(scalar).utf8))
      }
    }

    out.append(UInt8(ascii: "\""))
  }
}
