import AppKit
internal import GhosttyKit

/// What libghostty reports about one surface, copied out of the callback so it can cross to the
/// main actor.
enum SurfaceNotice: Sendable {
  case title(String)
  case workingDirectory(String)
  case notification(title: String, body: String)
  case commandFinished(exitCode: Int?, durationNanoseconds: UInt64)
  case bell
  case mouseShape(MouseShape)
  case cellSize(width: UInt32, height: UInt32)
  case configChanged
  case exited
}

enum MouseShape: Sendable {
  case standard
  case text
  case pointer
  case crosshair
  case notAllowed
}

/// A pointer handed back to libghostty later. It crosses actors only to be passed back unchanged.
struct OpaqueToken: @unchecked Sendable {
  let pointer: UnsafeMutableRawPointer?
}

/// The C callbacks that libghostty calls. They run on any thread, so each one copies what it needs
/// and hops to the main actor before it touches a Swift object. Nothing here unwinds through C.
enum GhosttyCallbacks {
  /// Built here, in a nonisolated context. A closure written inside a main-actor initializer would
  /// inherit that isolation, and libghostty calls these from its own threads.
  static func runtimeConfig(userdata: UnsafeMutableRawPointer) -> ghostty_runtime_config_s {
    ghostty_runtime_config_s(
      userdata: userdata,
      supports_selection_clipboard: false,
      wakeup_cb: { GhosttyCallbacks.wakeup($0) },
      action_cb: { GhosttyCallbacks.action($0, $1, $2) },
      read_clipboard_cb: { GhosttyCallbacks.readClipboard($0, $1, $2) },
      confirm_read_clipboard_cb: { GhosttyCallbacks.confirmReadClipboard($0, $1, $2, $3) },
      write_clipboard_cb: { GhosttyCallbacks.writeClipboard($0, $1, $2, $3, $4) },
      close_surface_cb: { GhosttyCallbacks.closeSurface($0, $1) })
  }

  static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }

    let target = Unmanaged<WakeupTarget>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async {
      MainActor.assumeIsolated { target.engine?.tick() }
    }
  }

  static func action(
    _ app: ghostty_app_t?, _ target: ghostty_target_s, _ action: ghostty_action_s
  ) -> Bool {
    guard target.tag == GHOSTTY_TARGET_SURFACE,
      let surface = target.target.surface,
      let userdata = ghostty_surface_userdata(surface)
    else { return false }

    let notice: SurfaceNotice

    switch action.tag {
    case GHOSTTY_ACTION_SET_TITLE:
      guard let title = action.action.set_title.title else { return true }

      notice = .title(String(cString: title))

    case GHOSTTY_ACTION_PWD:
      guard let pwd = action.action.pwd.pwd else { return true }

      notice = .workingDirectory(String(cString: pwd))

    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
      let raw = action.action.desktop_notification
      notice = .notification(
        title: raw.title.map { String(cString: $0) } ?? "",
        body: raw.body.map { String(cString: $0) } ?? "")

    case GHOSTTY_ACTION_COMMAND_FINISHED:
      let raw = action.action.command_finished
      notice = .commandFinished(
        exitCode: raw.exit_code < 0 ? nil : Int(raw.exit_code), durationNanoseconds: raw.duration)

    case GHOSTTY_ACTION_RING_BELL:
      notice = .bell

    case GHOSTTY_ACTION_MOUSE_SHAPE:
      notice = .mouseShape(Self.shape(action.action.mouse_shape))

    case GHOSTTY_ACTION_CONFIG_CHANGE:
      notice = .configChanged

    case GHOSTTY_ACTION_CELL_SIZE:
      let raw = action.action.cell_size
      notice = .cellSize(width: raw.width, height: raw.height)

    case GHOSTTY_ACTION_SCROLLBAR, GHOSTTY_ACTION_RENDER, GHOSTTY_ACTION_RENDERER_HEALTH,
      GHOSTTY_ACTION_MOUSE_VISIBILITY, GHOSTTY_ACTION_COLOR_CHANGE, GHOSTTY_ACTION_INITIAL_SIZE,
      GHOSTTY_ACTION_SIZE_LIMIT, GHOSTTY_ACTION_MOUSE_OVER_LINK,
      GHOSTTY_ACTION_PROGRESS_REPORT, GHOSTTY_ACTION_KEY_SEQUENCE, GHOSTTY_ACTION_KEY_TABLE:
      return true

    default:
      return false
    }

    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async {
      MainActor.assumeIsolated { view.receive(notice) }
    }
    return true
  }

  /// Runs on the main thread, from a call that the surface view itself made. It answers a paste, or
  /// the first half of an OSC 52 read. libghostty refuses to send OSC 52 data until the user
  /// confirms, so answering here with `confirmed` false is safe.
  static func readClipboard(
    _ userdata: UnsafeMutableRawPointer?, _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
  ) -> Bool {
    guard Thread.isMainThread, let userdata, location == GHOSTTY_CLIPBOARD_STANDARD else {
      return false
    }

    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    let token = OpaqueToken(pointer: state)
    return MainActor.assumeIsolated { view.answerClipboardRead(state: token) }
  }

  static func confirmReadClipboard(
    _ userdata: UnsafeMutableRawPointer?, _ string: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?, _ request: ghostty_clipboard_request_e
  ) {
    guard let userdata, let string else { return }

    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    let text = String(cString: string)
    let token = OpaqueToken(pointer: state)
    let kind: TerminalClipboardRequest.Kind =
      request == GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ
      ? .read : request == GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE ? .write : .unsafePaste

    DispatchQueue.main.async {
      MainActor.assumeIsolated { view.askAboutClipboard(kind: kind, text: text, state: token) }
    }
  }

  static func writeClipboard(
    _ userdata: UnsafeMutableRawPointer?, _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?, _ count: Int, _ confirm: Bool
  ) {
    guard let userdata, let content, count > 0 else { return }

    var plain: String?
    for index in 0..<count {
      let item = content[index]
      guard let mime = item.mime, let data = item.data, String(cString: mime) == "text/plain"
      else { continue }

      plain = String(cString: data)
    }

    guard let plain else { return }

    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async {
      MainActor.assumeIsolated { view.writeClipboard(plain, needsConfirmation: confirm) }
    }
  }

  /// libghostty calls this when the child ended. Freeing the surface from inside this callback
  /// would be a use after free, so the event always arrives on a later main-queue turn.
  static func closeSurface(_ userdata: UnsafeMutableRawPointer?, _ processAlive: Bool) {
    guard let userdata else { return }

    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async {
      MainActor.assumeIsolated { view.receive(.exited) }
    }
  }

  private static func shape(_ raw: ghostty_action_mouse_shape_e) -> MouseShape {
    switch raw {
    case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: return .text
    case GHOSTTY_MOUSE_SHAPE_POINTER: return .pointer
    case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: return .crosshair
    case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP: return .notAllowed
    default: return .standard
    }
  }
}

/// Lets the wakeup callback reach the engine without keeping it alive.
final class WakeupTarget: @unchecked Sendable {
  nonisolated(unsafe) weak var engine: GhosttyTerminalEngine?
}
