import AppKit
import Theme

/// The floating command palette: a search field over a list of results. It floats over the pane
/// area, so showing it never resizes a pane.
///
/// The view holds no commands. The window gives it entries and learns what the user chose. The
/// keyboard always belongs to the field. The arrow keys, Return, and Escape reach the list through
/// the field's delegate, and a click on a row never takes the keyboard from the field.
@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate, NSTableViewDataSource,
  NSTableViewDelegate
{
  static let width: CGFloat = 560
  static let rowHeight: CGFloat = 28
  static let fieldHeight: CGFloat = 40
  static let maximumVisibleRows = 8

  let field = NSTextField()

  private let scroll = NSScrollView()
  private let table = PaletteTableView()
  private let divider = NSView()
  private var palette: ThemePalette = .latte
  private var heightConstraint: NSLayoutConstraint?

  /// The entries on show, best first.
  private(set) var entries: [PaletteEntry] = []

  /// The entry Return would run. It is an ID, so a list that re-sorts keeps the same entry
  /// highlighted.
  private(set) var selection: PaletteEntryID?

  /// Runs when the search text changes, with the new text.
  var onQueryChange: ((String) -> Void)?

  /// Runs when the user chooses an enabled entry, with Return or a click.
  var onChoose: ((PaletteEntry) -> Void)?

  /// Runs when the user asks to hide the palette with Escape.
  var onDismiss: (() -> Void)?

  var query: String { field.stringValue }

  override var isFlipped: Bool { true }

  override var wantsUpdateLayer: Bool { true }

  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1

    field.placeholderString = "Search commands"
    field.font = .systemFont(ofSize: 15)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.delegate = self
    field.translatesAutoresizingMaskIntoConstraints = false
    field.setAccessibilityIdentifier("command-palette-field")
    addSubview(field)

    divider.wantsLayer = true
    divider.translatesAutoresizingMaskIntoConstraints = false
    addSubview(divider)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = Self.rowHeight
    table.intercellSpacing = .zero
    table.selectionHighlightStyle = .none
    table.backgroundColor = .clear
    table.refusesFirstResponder = true
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.action = #selector(rowClicked(_:))
    table.setAccessibilityIdentifier("command-palette-list")

    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll)

    let height = heightAnchor.constraint(equalToConstant: Self.fieldHeight)
    heightConstraint = height

    NSLayoutConstraint.activate([
      height,
      field.topAnchor.constraint(equalTo: topAnchor),
      field.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
      field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      divider.topAnchor.constraint(equalTo: field.bottomAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1),
      divider.leadingAnchor.constraint(equalTo: leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier("command-palette")
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func updateLayer() {
    layer?.backgroundColor = palette[.mantle].cgColor
    layer?.borderColor = palette[.surface1].cgColor
    divider.layer?.backgroundColor = palette[.surface1].cgColor
  }

  func apply(_ palette: ThemePalette) {
    self.palette = palette
    field.textColor = palette[.text].nsColor
    needsDisplay = true
    table.reloadData()
  }

  // MARK: Entries

  /// Shows a fresh list. The selection stays on its entry when the entry is still there and can
  /// run. Otherwise it moves to the first entry that can run.
  ///
  /// With no query, the first choice is the most recent tab other than the current one, so Return
  /// goes back to where the user was. With no other tab it is the first other entry that can run.
  func setEntries(_ entries: [PaletteEntry]) {
    self.entries = entries

    if let selection, entries.contains(where: { $0.id == selection && $0.isEnabled }) {
      // The same entry stays highlighted, wherever it sorted to.
    } else {
      selection = Self.firstChoice(in: entries, emptyQuery: PaletteRanking.isEmpty(query))
    }

    let rows = min(entries.count, Self.maximumVisibleRows)
    heightConstraint?.constant =
      Self.fieldHeight + CGFloat(rows) * Self.rowHeight + (rows > 0 ? 1 : 0)
    scroll.isHidden = entries.isEmpty
    divider.isHidden = entries.isEmpty

    table.reloadData()
    scrollToSelection()
  }

  private static func firstChoice(in entries: [PaletteEntry], emptyQuery: Bool) -> PaletteEntryID? {
    let enabled = entries.filter(\.isEnabled)

    guard emptyQuery else { return enabled.first?.id }

    let others = enabled.filter { !$0.isCurrent }

    return (others.first { $0.kind == .tab } ?? others.first ?? enabled.first)?.id
  }

  /// Clears the text and the selection for the next time the palette shows.
  func reset() {
    field.stringValue = ""
    selection = nil
    entries = []
    table.reloadData()
  }

  var selectedEntry: PaletteEntry? {
    entries.first { $0.id == selection }
  }

  private func moveSelection(by step: Int) {
    let enabled = entries.filter(\.isEnabled)

    guard !enabled.isEmpty else { return }

    let current = enabled.firstIndex { $0.id == selection } ?? (step > 0 ? -1 : enabled.count)
    let next = min(max(current + step, 0), enabled.count - 1)

    selection = enabled[next].id
    table.reloadData()
    scrollToSelection()
  }

  private func scrollToSelection() {
    if let row = entries.firstIndex(where: { $0.id == selection }) {
      table.scrollRowToVisible(row)
    }
  }

  private func chooseSelection() {
    guard let entry = selectedEntry, entry.isEnabled else { return }

    onChoose?(entry)
  }

  @objc private func rowClicked(_ sender: Any?) {
    let row = table.clickedRow

    guard entries.indices.contains(row), entries[row].isEnabled else { return }

    selection = entries[row].id
    chooseSelection()
  }

  // MARK: Field delegate

  func controlTextDidChange(_ notification: Notification) {
    // New text picks the first choice again. Only a re-list from the tabs keeps the highlight.
    selection = nil
    onQueryChange?(field.stringValue)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(by: 1)

    case #selector(NSResponder.moveUp(_:)):
      moveSelection(by: -1)

    case #selector(NSResponder.insertNewline(_:)):
      chooseSelection()

    case #selector(NSResponder.cancelOperation(_:)):
      onDismiss?()

    default:
      return false
    }

    return true
  }

  // MARK: Table

  func numberOfRows(in tableView: NSTableView) -> Int {
    entries.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    let view = PaletteRowView()
    view.configure(entries[row], selected: entries[row].id == selection, palette: palette)
    return view
  }
}

/// A table that never takes the keyboard, so the field keeps it while the user clicks a row.
private final class PaletteTableView: NSTableView {
  override var acceptsFirstResponder: Bool { false }
}

/// One result row: the title on the left and the kind on the right.
private final class PaletteRowView: NSView {
  private let title = NSTextField(labelWithString: "")
  private let kind = NSTextField(labelWithString: "")

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.cornerRadius = 6

    title.font = .systemFont(ofSize: 13)
    title.lineBreakMode = .byTruncatingTail
    title.translatesAutoresizingMaskIntoConstraints = false
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    addSubview(title)

    kind.font = .systemFont(ofSize: 11)
    kind.translatesAutoresizingMaskIntoConstraints = false
    kind.setContentHuggingPriority(.required, for: .horizontal)
    addSubview(kind)

    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      title.centerYAnchor.constraint(equalTo: centerYAnchor),
      kind.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      kind.centerYAnchor.constraint(equalTo: centerYAnchor),
      title.trailingAnchor.constraint(lessThanOrEqualTo: kind.leadingAnchor, constant: -12),
    ])

    setAccessibilityElement(true)
    setAccessibilityRole(.row)
    setAccessibilityIdentifier("command-palette-row")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func configure(_ entry: PaletteEntry, selected: Bool, palette: ThemePalette) {
    kind.stringValue = entry.kind.label

    let onAccent = palette.flavor == .latte ? palette[.base] : palette[.crust]

    let titleColor: NSColor
    let detailColor: NSColor

    if selected {
      layer?.backgroundColor = palette[.blue].cgColor
      titleColor = onAccent.nsColor
      detailColor = onAccent.nsColor
      kind.textColor = onAccent.nsColor
    } else {
      layer?.backgroundColor = NSColor.clear.cgColor
      titleColor = entry.isEnabled ? palette[.text].nsColor : palette[.overlay0].nsColor
      detailColor = palette[.overlay1].nsColor
      kind.textColor = palette[.overlay1].nsColor
    }

    let truncating = NSMutableParagraphStyle()
    truncating.lineBreakMode = .byTruncatingTail

    let text = NSMutableAttributedString(
      string: entry.title,
      attributes: [
        .foregroundColor: titleColor, .font: NSFont.systemFont(ofSize: 13),
        .paragraphStyle: truncating,
      ])

    if let detail = entry.detail, !detail.isEmpty {
      text.append(
        NSAttributedString(
          string: "  " + detail,
          attributes: [
            .foregroundColor: detailColor, .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: truncating,
          ]))
    }

    title.attributedStringValue = text

    setAccessibilityLabel(entry.title)
    setAccessibilityValue("\(entry.kind.label), \(entry.isEnabled ? "enabled" : "disabled")")
    setAccessibilityHelp(entry.detail)
    setAccessibilitySelected(selected)
  }
}
