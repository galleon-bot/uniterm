# uniterm

uniterm is a unified terminal emulator for macOS. It goes beyond a plain terminal.

A window holds a tree of resizable split panes. Each pane runs one applet. Planned applets include a terminal, a
browser, a data viewer, an image viewer, a text viewer, a map viewer, and a REPL. The REPL scripts uniterm itself in
Janet, a Lisp.

Each window also has a status bar and a command palette. Both can be docked in different places.

## Status

Early design. There is no code yet.

## Stack

- Swift, with AppKit for windows, panes, and applet hosting.
- SwiftUI for small views, such as status bar segments.
- [libghostty](https://ghostty.org) for terminal emulation.
- [Janet](https://janet-lang.org) for scripting.

## License

MIT. See [LICENSE](LICENSE).
