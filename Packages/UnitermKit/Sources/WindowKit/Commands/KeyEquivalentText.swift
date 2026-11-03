import AppKit

/// Spells a menu item's key equivalent the way the menu shows it, such as `⇧⌘P`.
enum KeyEquivalentText {
  /// Returns nil for an item with no key.
  static func spell(key: String, modifiers: NSEvent.ModifierFlags) -> String? {
    guard !key.isEmpty else { return nil }

    var text = ""

    if modifiers.contains(.control) { text += "\u{2303}" }
    if modifiers.contains(.option) { text += "\u{2325}" }
    if modifiers.contains(.shift) { text += "\u{21E7}" }
    if modifiers.contains(.command) { text += "\u{2318}" }

    guard let name = name(of: key) else { return nil }

    return text + name
  }

  /// A menu key can be one of AppKit's function-key characters, which live in the Unicode private
  /// use area and draw as nothing. Those get names. An unknown one has no name, so the hint is
  /// dropped and never shows a raw glyph.
  private static func name(of key: String) -> String? {
    if let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 {
      switch scalar.value {
      case 0xF704...0xF726: return "F\(scalar.value - 0xF704 + 1)"
      case 0xF727: return "Insert"
      case 0xF728: return "\u{2326}"
      case 0xF729: return "\u{2196}"
      case 0xF72B: return "\u{2198}"
      case 0xF72C: return "\u{21DE}"
      case 0xF72D: return "\u{21DF}"
      case 0xF746: return "Help"
      case 0xE000...0xF8FF where !(0xF700...0xF703).contains(scalar.value): return nil
      default: break
      }
    }

    switch key {
    case "\u{8}", "\u{7F}": return "\u{232B}"
    case "\r", "\u{3}": return "\u{21A9}"
    case "\t": return "\u{21E5}"
    case "\u{1B}": return "\u{238B}"
    case " ": return "Space"
    case "\u{F700}": return "\u{2191}"
    case "\u{F701}": return "\u{2193}"
    case "\u{F702}": return "\u{2190}"
    case "\u{F703}": return "\u{2192}"
    default: return key.uppercased()
    }
  }
}
