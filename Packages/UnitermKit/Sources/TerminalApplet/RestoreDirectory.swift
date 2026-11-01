import Foundation

/// Picks the directory a restored tab starts in.
///
/// The directory a shell reported is only a hint. It may belong to another machine after an ssh
/// login, or it may be gone. The first path of these that is absolute and still a directory wins:
/// the reported directory, then the tab's starting directory, then the home directory.
public enum RestoreDirectory {
  static func resolve(
    reported: String?, starting: String?, home: String, exists: (String) -> Bool
  ) -> String {
    for candidate in [reported, starting] {
      if let candidate, candidate.hasPrefix("/"), exists(candidate) {
        return candidate
      }
    }

    return home
  }

  /// True when the path is a directory on this machine.
  public static func isLocalDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return found && isDirectory.boolValue
  }
}
