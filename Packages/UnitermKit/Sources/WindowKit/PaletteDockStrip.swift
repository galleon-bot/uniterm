import AppKit

/// The docked palette's region: a strip across the window that holds the palette's field.
///
/// The strip paints nothing. The window's own background shows through. A click on the strip,
/// outside the field, takes no keyboard. While the palette is active, the window treats it like
/// any other click outside the palette.
///
/// A strip in the title bar row is part of the title bar. A drag on it outside the field moves
/// the window.
@MainActor
final class PaletteDockStrip: NSView {
  var isInTitleBar = false

  override var mouseDownCanMoveWindow: Bool { isInTitleBar }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { !isInTitleBar }
}
