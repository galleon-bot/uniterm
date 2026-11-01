import AppKit
import XCTest

@testable import WindowKit

@MainActor
final class NewPaneSheetLayoutTests: XCTestCase {
  private func textFields(in view: NSView) -> [NSTextField] {
    var found: [NSTextField] = []

    for subview in view.subviews {
      if let field = subview as? NSTextField { found.append(field) }

      found += textFields(in: subview)
    }

    return found
  }

  private func popups(in view: NSView) -> [NSPopUpButton] {
    var found: [NSPopUpButton] = []

    for subview in view.subviews {
      if let popup = subview as? NSPopUpButton { found.append(popup) }

      found += popups(in: subview)
    }

    return found
  }

  private func buttons(in view: NSView) -> [NSButton] {
    var found: [NSButton] = []

    for subview in view.subviews {
      if let button = subview as? NSButton, !(button is NSPopUpButton) { found.append(button) }

      found += buttons(in: subview)
    }

    return found
  }

  private func frame(_ view: NSView) -> NSRect {
    view.convert(view.bounds, to: nil)
  }

  /// Catches a subtitle that draws over the popup, a command field that lands on the subtitle or
  /// the buttons, and a sheet that does not resize when the field appears. Each mode must stack
  /// title, subtitle, popup, field, then buttons, with no overlap and a margin from the edges.
  func testSheetStacksItsPartsWithoutOverlapInBothModes() throws {
    let host = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
      backing: .buffered, defer: false)
    host.isReleasedWhenClosed = false
    host.orderFrontRegardless()

    NewPaneSheet.present(on: host) { _ in }
    let sheet = try XCTUnwrap(host.attachedSheet)
    defer { host.endSheet(sheet) }

    let content = try XCTUnwrap(sheet.contentView)
    let popup = try XCTUnwrap(popups(in: content).first)

    func check(program: Bool) throws {
      content.layoutSubtreeIfNeeded()

      let fields = textFields(in: content)
      let title = try XCTUnwrap(fields.first { $0.stringValue == "Open a new pane" })
      let subtitle = try XCTUnwrap(fields.first { $0.stringValue == "Choose what the pane runs." })
      let command = fields.first { $0.placeholderString?.hasPrefix("Command") == true }
      let buttonFrames = buttons(in: content).map(frame)
      XCTAssertEqual(buttonFrames.count, 2)

      var ordered = [frame(title), frame(subtitle), frame(popup)]
      if program {
        ordered.append(frame(try XCTUnwrap(command)))
      }
      ordered.append(buttonFrames.max { $0.maxY < $1.maxY }!)

      for (above, below) in zip(ordered, ordered.dropFirst()) {
        XCTAssertGreaterThanOrEqual(
          above.minY, below.maxY, "\(above) overlaps or sits below \(below), program=\(program)")
      }

      if !program {
        XCTAssertTrue(command?.isHidden ?? true, "command field shows in shell mode")
      }

      let bounds = content.bounds
      for part in ordered {
        XCTAssertGreaterThanOrEqual(part.minX, 15)
        XCTAssertLessThanOrEqual(part.maxX, bounds.maxX - 15)
        XCTAssertGreaterThanOrEqual(part.minY, 10)
        XCTAssertLessThanOrEqual(part.maxY, bounds.maxY - 10)
      }
    }

    try check(program: false)
    let shellHeight = content.bounds.height

    popup.selectItem(at: 1)
    _ = popup.sendAction(popup.action, to: popup.target)
    try check(program: true)
    XCTAssertGreaterThan(content.bounds.height, shellHeight, "sheet did not grow for the field")

    popup.selectItem(at: 0)
    _ = popup.sendAction(popup.action, to: popup.target)
    try check(program: false)
    XCTAssertEqual(content.bounds.height, shellHeight, accuracy: 1, "sheet did not shrink back")
  }
}
