import AppKit
import NotifulCore

/// A visual configuration window. It reads RECENT notifications from the DB so you can add sources by
/// clicking a real notification, rather than hand-editing JSON. The raw JSON is still available via
/// "Open config file".
final class ConfigWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow!
    private let database: NotificationDatabase?
    private var config: Config
    private let onSave: (Config) -> Void

    private var recent: [NotificationRecord] = []
    private var recentTable: NSTableView!
    private var sourcesTable: NSTableView!

    // Buttons whose enabled-state depends on a row being selected (#6).
    private var recentDependentButtons: [NSButton] = []
    private var sourceDependentButtons: [NSButton] = []

    // Empty-state placeholders shown over each table when it has no rows (#7).
    private var recentPlaceholder: NSTextField!
    private var sourcesPlaceholder: NSTextField!

    init(database: NotificationDatabase?, current: Config, onSave: @escaping (Config) -> Void) {
        self.database = database
        self.config = current
        self.onSave = onSave
        super.init()
        buildWindow()
    }

    func refresh(current: Config) {
        config = current
        reloadRecent()
        sourcesTable?.reloadData()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        reloadRecent()
        sourcesTable.reloadData()
    }

    // MARK: - Build UI

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Notiful — Configuration"
        window.center()
        window.isReleasedWhenClosed = false

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let recentLabel = label("Recent notifications — pick one, then add it as a source to watch:")
        let recentScroll = makeRecentTable()
        let (recentButtons, recentBtns) = makeButtonRow([
            ("Add this app", #selector(addByApp), true),
            ("Add by matching text…", #selector(addBySender), true),
            ("Refresh", #selector(refreshClicked), false),
        ])
        recentDependentButtons = recentBtns

        let sourcesLabel = label("Sources you’re watching:")
        let sourcesScroll = makeSourcesTable()
        let (sourcesButtons, sourceBtns) = makeButtonRow([
            ("Edit…", #selector(editSource), true),
            ("Auto-copy on/off", #selector(toggleSourceAutoCopy), true),
            ("Run command…", #selector(setCommand), true),
            ("Remove", #selector(removeSource), true),
        ])
        sourceDependentButtons = sourceBtns

        let (bottom, _) = makeButtonRow([
            ("Edit raw config (JSON)", #selector(openRawConfig), false),
            ("Done", #selector(closeWindow), false),
        ])

        let stack = NSStackView(views: [
            recentLabel, recentScroll, recentButtons,
            sourcesLabel, sourcesScroll, sourcesButtons,
            bottom,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            recentScroll.heightAnchor.constraint(equalToConstant: 230),
            sourcesScroll.heightAnchor.constraint(equalToConstant: 150),
            recentScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            sourcesScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
        ])
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 12)
        return l
    }

    /// Builds a horizontal button row. Each item is (title, selector, dependsOnSelection).
    /// Returns the row plus the subset of buttons that depend on a row being selected (#6).
    private func makeButtonRow(_ items: [(String, Selector, Bool)]) -> (NSView, [NSButton]) {
        var dependent: [NSButton] = []
        let buttons = items.map { (title, sel, depends) -> NSButton in
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded
            if depends { b.isEnabled = false; dependent.append(b) }
            return b
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        return (row, dependent)
    }

    private func makeRecentTable() -> NSScrollView {
        let table = NSTableView()
        addColumn(table, "app", "App", 130)
        addColumn(table, "title", "Title", 130)
        addColumn(table, "subtitle", "Subtitle", 120)
        addColumn(table, "body", "Body", 220)
        addColumn(table, "match", "Matches", 70)
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        recentTable = table
        let s = scroll(table)
        recentPlaceholder = placeholder(over: s)
        return s
    }

    private func makeSourcesTable() -> NSScrollView {
        let table = NSTableView()
        addColumn(table, "name", "Name", 130)
        addColumn(table, "smatch", "Match", 280)
        addColumn(table, "auto", "Auto-copy", 70)
        addColumn(table, "cmd", "Command", 180)
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        sourcesTable = table
        let s = scroll(table)
        sourcesPlaceholder = placeholder(over: s)
        return s
    }

    /// A centered, dimmed message shown over an empty table; hidden once it has rows (#7).
    private func placeholder(over scrollView: NSScrollView) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.alignment = .center
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(field)
        NSLayoutConstraint.activate([
            field.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            field.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -40),
        ])
        return field
    }

    private func addColumn(_ table: NSTableView, _ id: String, _ title: String, _ width: CGFloat) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        col.title = title
        col.width = width
        table.addTableColumn(col)
    }

    private func scroll(_ table: NSTableView) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = table
        s.hasVerticalScroller = true
        s.borderType = .bezelBorder
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    // MARK: - Data

    private var canReadDB = true

    private func reloadRecent() {
        guard let db = database, db.canRead() else {
            canReadDB = false; recent = []; recentTable?.reloadData(); updateUIState(); return
        }
        canReadDB = true
        let own = (Bundle.main.bundleIdentifier ?? "com.notiful.app").lowercased()
        recent = ((try? db.fetchRecords(limit: 60)) ?? [])
            .filter { $0.bundleID.lowercased() != own }  // hide our own notifications
        recentTable?.reloadData()
        updateUIState()
    }

    /// Keep empty-state placeholders and selection-dependent buttons in sync with the tables (#6, #7).
    private func updateUIState() {
        if !canReadDB {
            recentPlaceholder?.stringValue = "Can’t read notifications yet — grant Full Disk Access from Notiful’s menu, then Refresh."
        } else {
            recentPlaceholder?.stringValue = "No notifications yet. When an app shows one, it appears here."
        }
        recentPlaceholder?.isHidden = !recent.isEmpty

        sourcesPlaceholder?.stringValue = "No sources yet. Select a notification above and click “Add this app”."
        sourcesPlaceholder?.isHidden = !config.sources.isEmpty

        let hasRecent = (recentTable?.selectedRow ?? -1) >= 0
        recentDependentButtons.forEach { $0.isEnabled = hasRecent }
        let hasSource = (sourcesTable?.selectedRow ?? -1) >= 0
        sourceDependentButtons.forEach { $0.isEnabled = hasSource }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateUIState()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === recentTable ? recent.count : config.sources.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        let text: String
        if tableView === recentTable {
            let r = recent[row]
            switch id {
            case "app": text = appName(r.bundleID)
            case "title": text = r.title
            case "subtitle": text = r.subtitle
            case "body": text = r.body
            case "match": text = SourceMatcher.match(record: r, sources: config.sources) != nil ? "✓" : ""
            default: text = ""
            }
        } else {
            let s = config.sources[row]
            switch id {
            case "name": text = s.name
            case "smatch": text = matchSummary(s.match)
            case "auto": text = s.actions.autoCopy ? "on" : ""
            case "cmd": text = s.actions.runCommand ?? ""
            default: text = ""
            }
        }
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text.isEmpty ? nil : text
        return field
    }

    private func matchSummary(_ m: SourceMatch) -> String {
        var parts: [String] = []
        if let a = m.appBundleIds, !a.isEmpty {
            parts.append("App is \(a.map(appName).joined(separator: " or "))")
        }
        if let s = m.senderContains, !s.isEmpty { parts.append("Sender contains “\(s.joined(separator: "” or “"))”") }
        if let t = m.titleContains, !t.isEmpty { parts.append("Title contains “\(t.joined(separator: "” or “"))”") }
        if let b = m.bodyContains, !b.isEmpty { parts.append("Body contains “\(b.joined(separator: "” or “"))”") }
        return parts.joined(separator: " · ")
    }

    private func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    // MARK: - Actions (recent → add source)

    @objc private func refreshClicked() { reloadRecent() }

    private func selectedRecent() -> NotificationRecord? {
        let row = recentTable.selectedRow
        guard row >= 0, row < recent.count else { warn("Select a recent notification first."); return nil }
        return recent[row]
    }

    @objc private func addByApp() {
        guard let r = selectedRecent() else { return }
        let source = Source(name: appName(r.bundleID),
                            match: SourceMatch(appBundleIds: [r.bundleID]),
                            actions: SourceActions())
        appendSource(source)
    }

    @objc private func addBySender() {
        guard let r = selectedRecent() else { return }
        // Prefer the subtitle marker (Google Voice puts "voice.google.com" there); else the title.
        let suggested = !r.subtitle.isEmpty ? r.subtitle : r.title
        guard let text = prompt(title: "Add by sender text",
                                message: "Match notifications whose title or subtitle contains:",
                                default: suggested), !text.isEmpty else { return }
        let source = Source(name: text,
                            match: SourceMatch(senderContains: [text]),
                            actions: SourceActions())
        appendSource(source)
    }

    private func appendSource(_ source: Source) {
        config.sources.append(source)
        commit()
    }

    // MARK: - Actions (sources)

    private func selectedSourceIndex() -> Int? {
        let row = sourcesTable.selectedRow
        guard row >= 0, row < config.sources.count else { warn("Select a configured source first."); return nil }
        return row
    }

    @objc private func removeSource() {
        guard let i = selectedSourceIndex() else { return }
        let name = config.sources[i].name
        let confirm = NSAlert()
        confirm.messageText = "Remove “\(name)”?"
        confirm.informativeText = "Notiful will stop watching this source. You can add it again later."
        confirm.addButton(withTitle: "Remove")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        config.sources.remove(at: i)
        commit()
    }

    /// Rename a source and edit the text it matches on (#3). App-bundle matches stay as-is; this
    /// edits the human-entered "matching text" sources, which is where typos actually happen.
    @objc private func editSource() {
        guard let i = selectedSourceIndex() else { return }
        var source = config.sources[i]

        guard let newName = prompt(title: "Edit source",
                                   message: "Name shown in Notiful:",
                                   default: source.name), !newName.isEmpty else { return }
        source.name = newName

        // Only offer to edit matching text for text-based sources (not app-bundle matches).
        if let sender = source.match.senderContains, !sender.isEmpty {
            guard let text = prompt(title: "Edit matching text",
                                    message: "Match notifications whose title or subtitle contains:",
                                    default: sender.joined(separator: ", ")) else { return }
            let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            source.match.senderContains = parts.isEmpty ? nil : parts
        }

        config.sources[i] = source
        commit()
    }

    @objc private func setCommand() {
        guard let i = selectedSourceIndex() else { return }
        let current = config.sources[i].actions.runCommand ?? ""
        guard let cmd = promptMultiline(
                title: "Run a command when a code is found",
                message: "Shell command to run. These variables are available:\n"
                    + "  $NOTIFUL_CODE — the detected code\n"
                    + "  $NOTIFUL_SOURCE — this source’s name\n"
                    + "  $NOTIFUL_APP, $NOTIFUL_TITLE, $NOTIFUL_SUBTITLE, $NOTIFUL_BODY\n"
                    + "Leave empty to remove the command.",
                default: current) else { return }
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        config.sources[i].actions.runCommand = trimmed.isEmpty ? nil : trimmed
        commit()
    }

    @objc private func toggleSourceAutoCopy() {
        guard let i = selectedSourceIndex() else { return }
        config.sources[i].actions.autoCopy.toggle()
        commit()
    }

    @objc private func openRawConfig() {
        _ = ConfigStore.loadOrCreate()
        NSWorkspace.shared.open(ConfigStore.configURL)
    }

    @objc private func closeWindow() { window.close() }

    /// Persist + notify the app, then refresh both tables.
    private func commit() {
        onSave(config)
        sourcesTable.reloadData()
        recentTable.reloadData()  // match column may have changed
        updateUIState()
    }

    // MARK: - Small helpers

    private func warn(_ message: String) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); a.runModal()
    }

    private func prompt(title: String, message: String, default def: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.stringValue = def
        a.accessoryView = field
        a.window.initialFirstResponder = field
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Like `prompt`, but with a multiline, scrollable text view — for shell commands (#11).
    private func promptMultiline(title: String, message: String, default def: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 90))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.string = def
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        a.accessoryView = scroll
        a.window.initialFirstResponder = textView
        return a.runModal() == .alertFirstButtonReturn ? textView.string : nil
    }
}
