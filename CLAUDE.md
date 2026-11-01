# uniterm

uniterm is a unified terminal emulator for macOS. See [README.md](README.md) for the overview.

## Coding Standards

@~/projects/coding_agent_standards/profiles/swift-macos-app.md
@~/projects/coding_agent_standards/languages/lisp.md
@~/projects/coding_agent_standards/languages/janet.md
@~/projects/coding_agent_standards/languages/lisp-embedding.md

These imports stand in for a future `swift-macos-janet-host` profile. Promote them to a real profile once the
combination is proven here.

## Stack Decisions

- Swift is the host language.
- AppKit owns the window, the pane tree, and applet hosting. The `swift-macos-app` profile assumes SwiftUI. Here, its
  SwiftUI rules apply only to SwiftUI code.
- SwiftUI is allowed for small leaf views, such as status bar segments and widgets.
- libghostty provides terminal emulation. Its API is unstable. Pin it to an exact version.
- Janet is the embedded scripting language. It backs the REPL applet and the scripting API.

## Git

- You may commit without asking first.
- Keep each commit to one logical change.
- Pushing still needs approval.
