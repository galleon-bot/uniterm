import AppKit
import AppletKit

@MainActor
final class FakeApplet: Applet {
  let typeID = "fake"
  let view = NSView()
  var title = "Fake"
  var segments: [AppletSegment] = []
  var isRunningSomething = false
  weak var host: (any AppletHost)?
  var started = false
  var closed = false

  func start() { started = true }
  func close() { closed = true }
  func detach() {}
  func reattach() {}
  func focus() {}
  func describe() -> AppletDescription {
    AppletDescription(type: "fake", version: 1, payload: .null)
  }
}
