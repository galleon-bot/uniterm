import AppKit

/// The docked palette's region: a strip across the window that holds the palette's field.
///
/// The strip paints nothing. The window's own background shows through. A click on the strip,
/// outside the field, takes no keyboard. While the palette is active, the window treats it like
/// any other click outside the palette.
@MainActor
final class PaletteDockStrip: NSView {
  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
