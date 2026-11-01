import AppKit

/// An sRGB color with 8 bits per channel.
public struct ThemeColor: Sendable, Hashable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(hex: UInt32) {
    red = UInt8((hex >> 16) & 0xFF)
    green = UInt8((hex >> 8) & 0xFF)
    blue = UInt8(hex & 0xFF)
  }

  /// The color as lowercase `#rrggbb`.
  public var hexString: String {
    String(format: "#%02x%02x%02x", red, green, blue)
  }

  public var nsColor: NSColor {
    NSColor(
      srgbRed: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: 1)
  }

  public var cgColor: CGColor {
    nsColor.cgColor
  }
}
