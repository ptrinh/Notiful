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

        let recentLabel = label("Recent notifications — select one, then add it as a source:")
        let recentScroll = makeRecentTable()
        let recentButtons = makeButtonRow([
            ("Add by App (native apps)", #selector(addByApp)),
            ("Add by Sender text (browser sources)", #selector(addBySender)),
            ("Refresh", #selector(refreshClicked)),
        ])

        let sourcesLabel = label("Configured sources:")
        let sourcesScroll = makeSourcesTable()
        let sourcesButtons = makeButtonRow([
            ("Remove", #selector(removeSource)),
            ("Set command on event", #selector(setCommand)),
            ("Toggle Auto-copy to clipboard", #selector(toggleSourceAutoCopy)),
        ])

        let bottom = makeButtonRow([
            ("Open config file (raw JSON)", #selector(openRawConfig)),
            ("Done", #selector(closeWindow)),
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

    private func makeButtonRow(_ items: [(String, Selector)]) -> NSView {
        let buttons = items.map { (title, sel) -> NSButton in
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded
            return b
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        return row
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
        return scroll(table)
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
        return scroll(table)
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

    private func reloadRecent() {
        guard let db = database, db.canRead() else { recent = []; recentTable?.reloadData(); return }
        let own = (Bundle.main.bundleIdentifier ?? "com.notiful.app").lowercased()
        recent = ((try? db.fetchRecords(limit: 60)) ?? [])
            .filter { $0.bundleID.lowercased() != own }  // hide our own notifications
        recentTable?.reloadData()
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
        if let a = m.appBundleIds, !a.isEmpty { parts.append("app: \(a.joined(separator: ","))") }
        if let s = m.senderContains, !s.isEmpty { parts.append("sender~: \(s.joined(separator: ","))") }
        if let t = m.titleContains, !t.isEmpty { parts.append("title~: \(t.joined(separator: ","))") }
        if let b = m.bodyContains, !b.isEmpty { parts.append("body~: \(b.joined(separator: ","))") }
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
        config.sources.remove(at: i)
        commit()
    }

    @objc private func setCommand() {
        guard let i = selectedSourceIndex() else { return }
        let current = config.sources[i].actions.runCommand ?? ""
        guard let cmd = prompt(title: "Run command on new code",
                               message: "Shell command. Available: $NOTIFUL_CODE, $NOTIFUL_SOURCE, $NOTIFUL_APP, $NOTIFUL_TITLE, $NOTIFUL_SUBTITLE, $NOTIFUL_BODY.\nLeave empty to remove.",
                               default: current) else { return }
        config.sources[i].actions.runCommand = cmd.isEmpty ? nil : cmd
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
}
