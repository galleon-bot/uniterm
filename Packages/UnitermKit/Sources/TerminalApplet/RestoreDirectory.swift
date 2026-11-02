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
      if let found = local(candidate, exists: exists) {
        return found
      }
    }

    return home
  }

  /// The path when it is absolute and still a directory, and nil otherwise. A path a shell reported
  /// after an ssh login, such as `me@host:/srv`, or one that is gone, is not usable here.
  static func local(_ path: String?, exists: (String) -> Bool) -> String? {
    guard let path, path.hasPrefix("/"), exists(path) else { return nil }

    return path
  }

  /// True when the path is a directory on this machine.
  public static func isLocalDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return found && isDirectory.boolValue
  }
}
