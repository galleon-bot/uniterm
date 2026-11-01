import CoreGraphics

/// A screen as the clamp sees it.
public struct ScreenArea: Sendable, Equatable {
  /// The whole screen.
  public var frame: CGRect

  /// The part a window may use, without the menu bar and the Dock.
  public var visibleFrame: CGRect

  public init(frame: CGRect, visibleFrame: CGRect) {
    self.frame = frame
    self.visibleFrame = visibleFrame
  }
}

/// Puts a saved window frame on a screen that exists now.
public enum FrameClamp {
  /// Returns a frame that lies fully inside the visible frame of one screen.
  ///
  /// A frame already inside one visible frame stays as it is. Otherwise the screen is the one whose
  /// frame equals the saved screen, then the one that overlaps the frame most, then the first one
  /// listed, which is the main screen. The frame is grown to `minimumSize`, then cut down to fit
  /// the screen, then moved inside it. The screen wins over the minimum, since a window larger
  /// than its screen is not usable.
  ///
  /// With no screens at all the frame comes back unchanged.
  public static func clamp(
    _ frame: CGRect, savedScreen: CGRect?, screens: [ScreenArea], minimumSize: CGSize = .zero
  ) -> CGRect {
    guard let first = screens.first else { return frame }

    let width = max(frame.width, minimumSize.width)
    let height = max(frame.height, minimumSize.height)
    let wanted = CGRect(x: frame.minX, y: frame.minY, width: width, height: height)

    if screens.contains(where: { $0.visibleFrame.contains(wanted) }) {
      return wanted
    }

    let target = screen(for: wanted, savedScreen: savedScreen, screens: screens) ?? first
    let visible = target.visibleFrame

    let fitted = CGSize(width: min(width, visible.width), height: min(height, visible.height))

    let x = min(max(wanted.minX, visible.minX), visible.maxX - fitted.width)
    let y = min(max(wanted.minY, visible.minY), visible.maxY - fitted.height)

    return CGRect(x: x, y: y, width: fitted.width, height: fitted.height)
  }

  private static func screen(
    for frame: CGRect, savedScreen: CGRect?, screens: [ScreenArea]
  ) -> ScreenArea? {
    if let savedScreen, let same = screens.first(where: { $0.frame == savedScreen }) {
      return same
    }

    var best: (screen: ScreenArea, area: CGFloat)?

    for candidate in screens {
      let overlap = candidate.visibleFrame.intersection(frame)
      let area = overlap.isNull ? 0 : overlap.width * overlap.height

      if area > (best?.area ?? 0) { best = (candidate, area) }
    }

    return best?.screen
  }
}
