import Foundation

/// Runs a closure after a delay and returns a way to cancel it. It matches the shape of the status
/// center's scheduler, so a test fires wakeups by hand.
public typealias LayoutScheduler =
  @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) ->
  @MainActor () ->
  Void

/// Saves the layout after a short quiet period, and at once when asked.
///
/// Every layout change restarts the wait, so a burst of changes writes once. A stream of changes
/// that never goes quiet still writes once the maximum wait has passed since the first of them.
///
/// The caller asks for an immediate save on quit, which also drops any wait still pending.
///
/// Saving stays off until the caller turns it on, so a half-restored layout never replaces the
/// file.
@MainActor
public final class LayoutSaver {
  public static let defaultScheduler: LayoutScheduler = { delay, action in
    let task = Task { @MainActor in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }

      action()
    }

    return { task.cancel() }
  }

  /// How long the layout must stay unchanged before it is written.
  public let debounce: TimeInterval

  /// The longest a change waits for a save, however many changes follow it.
  public let maximumWait: TimeInterval

  private let scheduler: LayoutScheduler
  private let snapshot: @MainActor () -> SavedLayout
  private let write: @MainActor (SavedLayout) throws -> Void
  private let onFailure: @MainActor (any Error) -> Void
  private var cancelPending: (@MainActor () -> Void)?
  private var cancelDeadline: (@MainActor () -> Void)?
  private var lastFailure: String?

  public private(set) var isEnabled = false

  /// `snapshot` reads the layout now. `write` stores it. A failed write goes to `onFailure`, once
  /// for each distinct failure until a write succeeds.
  public init(
    debounce: TimeInterval = 1, maximumWait: TimeInterval = 10,
    scheduler: @escaping LayoutScheduler = LayoutSaver.defaultScheduler,
    snapshot: @escaping @MainActor () -> SavedLayout,
    write: @escaping @MainActor (SavedLayout) throws -> Void,
    onFailure: @escaping @MainActor (any Error) -> Void
  ) {
    self.debounce = debounce
    self.maximumWait = maximumWait
    self.scheduler = scheduler
    self.snapshot = snapshot
    self.write = write
    self.onFailure = onFailure
  }

  public func enable() {
    isEnabled = true
  }

  /// Turns saving off and drops a pending save. Nothing is written afterwards.
  public func disable() {
    isEnabled = false
    cancelWaits()
  }

  private func cancelWaits() {
    cancelPending?()
    cancelPending = nil
    cancelDeadline?()
    cancelDeadline = nil
  }

  /// The layout changed. A save follows once the quiet period passes.
  public func layoutDidChange() {
    guard isEnabled else { return }

    cancelPending?()
    cancelPending = scheduler(debounce) { [weak self] in
      self?.saveNow()
    }

    if cancelDeadline == nil {
      cancelDeadline = scheduler(maximumWait) { [weak self] in
        self?.saveNow()
      }
    }
  }

  /// Writes the layout now. A save pending from a change is dropped, since this one covers it.
  public func saveNow() {
    guard isEnabled else { return }

    cancelWaits()

    do {
      try write(snapshot())
      lastFailure = nil
    } catch {
      let text = "\(error)"

      if text != lastFailure {
        lastFailure = text
        onFailure(error)
      }
    }
  }
}
