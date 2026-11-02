import Carbon

/// The current keyboard input source. A key event can change it, for example when an input method
/// switches itself on. The key handler uses the id to tell such an event from typing.
enum KeyboardLayout {
  static var id: String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    else { return nil }

    return unsafeBitCast(pointer, to: CFString.self) as String
  }
}
