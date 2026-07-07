import SwiftUI
import NotifulCore

// MARK: - Root

/// The settings UI: a native two-tab layout — Sources (pick real notifications, manage watched
/// sources) and Settings (clipboard, privacy, detection, advanced).
struct ConfigView: View {
    @EnvironmentObject private var model: ConfigModel

    var body: some View {
        TabView {
            SourcesTab()
                .tabItem { Label("Sources", systemImage: "bell.badge") }
            GeneralSettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 740, minHeight: 600)
    }
}

// MARK: - Sources tab

struct SourcesTab: View {
    @EnvironmentObject private var model: ConfigModel

    @State private var selectedRecent: Int64?
    @State private var editorContext: EditorContext?
    @State private var removeIndex: Int?
    @State private var noCodeAlert = false

    /// Sheet payload: nil index = append a new source, otherwise edit in place.
    struct EditorContext: Identifiable {
        let id = UUID()
        var index: Int?
        var source: Source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Notifications")
                .font(.headline)
            Text("Pick a real notification, then add its app — or its sender text — as a watched source.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            recentTable
                .frame(minHeight: 220)

            HStack(spacing: 8) {
                Button {
                    if let r = selectedRecentRecord { model.addByApp(r) }
                } label: {
                    Label("Add This App", systemImage: "plus.app")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRecentRecord == nil)

                Button {
                    if let r = selectedRecentRecord {
                        let suggested = !r.subtitle.isEmpty ? r.subtitle : r.title
                        editorContext = EditorContext(index: nil, source: Source(
                            name: suggested,
                            match: SourceMatch(senderContains: [suggested])))
                    }
                } label: {
                    Label("Add by Matching Text…", systemImage: "textformat.abc")
                }
                .disabled(selectedRecentRecord == nil)

                Spacer()

                Button {
                    model.reloadRecent()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload recent notifications")
            }

            Divider().padding(.vertical, 4)

            Text("Watched Sources")
                .font(.headline)

            sourcesList
                .frame(minHeight: 150)
        }
        .padding(16)
        .sheet(item: $editorContext) { ctx in
            SourceEditorSheet(
                title: ctx.index == nil ? "Add Source" : "Edit Source",
                source: ctx.source
            ) { saved in
                if let i = ctx.index { model.update(saved, at: i) } else { model.append(saved) }
            }
        }
        .alert("Remove this source?", isPresented: Binding(
            get: { removeIndex != nil },
            set: { if !$0 { removeIndex = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let i = removeIndex { model.removeSource(at: i) }
                removeIndex = nil
            }
            Button("Cancel", role: .cancel) { removeIndex = nil }
        } message: {
            if let i = removeIndex, model.config.sources.indices.contains(i) {
                Text("Notiful will stop watching “\(model.config.sources[i].name)”. You can add it again later.")
            }
        }
        .alert("No code detected", isPresented: $noCodeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Notiful didn’t find a one-time code in this notification.")
        }
    }

    private var selectedRecentRecord: NotificationRecord? {
        guard let id = selectedRecent else { return nil }
        return model.recent.first { $0.id == id }?.record
    }

    private var recentTable: some View {
        Table(model.recent, selection: $selectedRecent) {
            TableColumn("App") { row in
                Text(model.appName(row.record.bundleID))
            }
            .width(min: 80, ideal: 120)

            TableColumn("Title") { row in
                Text(row.record.title)
            }
            .width(min: 80, ideal: 130)

            TableColumn("Body") { row in
                Text(row.record.body.replacingOccurrences(of: "\n", with: " "))
                    .help(row.record.body)
            }
            .width(min: 160, ideal: 260)

            TableColumn("When") { row in
                Text(Self.relativeTime(row.record.deliveredDate))
                    .foregroundColor(.secondary)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Watched") { row in
                if model.matches(row.record) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .help("A watched source matches this notification")
                        Button {
                            if !model.test(row.record) { noCodeAlert = true }
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Replay this notification — banner and auto-copy, exactly as if it just arrived")
                    }
                }
            }
            .width(min: 70, ideal: 90)
        }
        .overlay {
            if model.recent.isEmpty {
                EmptyHint(
                    icon: model.canReadDB ? "bell.slash" : "lock.shield",
                    title: model.canReadDB ? "No notifications yet" : "Can’t read notifications yet",
                    message: model.canReadDB
                        ? "When an app shows a notification, it appears here."
                        : "Grant Full Disk Access from Notiful’s menu, then click Refresh.")
            }
        }
    }

    @ViewBuilder
    private var sourcesList: some View {
        if model.config.sources.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                EmptyHint(icon: "plus.circle",
                          title: "No sources yet",
                          message: "Select a notification above and click “Add This App”.")
            }
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(model.config.sources.enumerated()), id: \.offset) { i, source in
                        sourceRow(source, index: i)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sourceRow(_ source: Source, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundColor(.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .fontWeight(.medium)
                Text(model.matchSummary(source.match))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(model.matchSummary(source.match))
            }

            Spacer()

            if source.actions.autoCopy { Pill(text: "Auto-copy", color: .blue) }
            if source.otpRegex != nil { Pill(text: "Regex", color: .orange) }
            if source.actions.runCommand != nil { Pill(text: "Command", color: .purple) }
            if !source.actions.showActionableNotification { Pill(text: "Silent", color: .gray) }

            Button {
                editorContext = EditorContext(index: index, source: source)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit this source")

            Button {
                removeIndex = index
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this source")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeTime(_ macAbsolute: Double) -> String {
        let date = Date(timeIntervalSinceReferenceDate: macAbsolute)
        return relFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Source editor sheet

/// Full per-source editor: every field that previously required hand-editing config.json —
/// name, all four match criteria, the per-source regex, and every action toggle.
struct SourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (Source) -> Void

    @State private var name: String
    @State private var bundleIDs: String
    @State private var sender: String
    @State private var titleText: String
    @State private var bodyText: String
    @State private var regex: String
    @State private var autoCopy: Bool
    @State private var showBanner: Bool
    @State private var openButton: Bool
    @State private var openTarget: String
    @State private var command: String

    init(title: String, source: Source, onSave: @escaping (Source) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: source.name)
        _bundleIDs = State(initialValue: (source.match.appBundleIds ?? []).joined(separator: ", "))
        _sender = State(initialValue: (source.match.senderContains ?? []).joined(separator: ", "))
        _titleText = State(initialValue: (source.match.titleContains ?? []).joined(separator: ", "))
        _bodyText = State(initialValue: (source.match.bodyContains ?? []).joined(separator: ", "))
        _regex = State(initialValue: source.otpRegex ?? "")
        _autoCopy = State(initialValue: source.actions.autoCopy)
        _showBanner = State(initialValue: source.actions.showActionableNotification)
        _openButton = State(initialValue: source.actions.openButton)
        _openTarget = State(initialValue: source.actions.openTarget ?? "")
        _command = State(initialValue: source.actions.runCommand ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                } header: {
                    Text(title).font(.headline)
                }

                Section("Match — a notification matches when ANY of these hit") {
                    TextField("App bundle IDs (comma-separated)", text: $bundleIDs)
                        .help("e.g. com.tdesktop.Telegram — for native apps")
                    TextField("Sender / title or subtitle contains", text: $sender)
                        .help("e.g. voice.google.com — for browser notifications")
                    TextField("Title contains", text: $titleText)
                    TextField("Body must also contain (optional gate)", text: $bodyText)
                }

                Section("Detection") {
                    TextField("Custom code pattern (regex, optional)", text: $regex)
                        .font(.system(.body, design: .monospaced))
                    Text("Leave empty to use smart detection. Capture group 1 wins, else the whole match.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Actions") {
                    Toggle("Copy the code to the clipboard automatically", isOn: $autoCopy)
                    Toggle("Show a Notiful banner when a code is found", isOn: $showBanner)
                    Toggle("Add an “Open Source” button to the banner", isOn: $openButton)
                    if openButton {
                        TextField("Open target (URL or bundle ID)", text: $openTarget)
                            .help("e.g. https://voice.google.com or com.tdesktop.Telegram")
                    }
                }

                Section("Run a command when a code is found (optional)") {
                    TextEditor(text: $command)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 54)
                    Text("Available: $NOTIFUL_CODE, $NOTIFUL_SOURCE, $NOTIFUL_APP, $NOTIFUL_TITLE, $NOTIFUL_SUBTITLE, $NOTIFUL_BODY")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !hasCriteria {
                    Label("Add at least one match criterion", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(buildSource())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasCriteria)
            }
            .padding(12)
        }
        .frame(width: 540, height: 560)
    }

    private var hasCriteria: Bool {
        !(parseList(bundleIDs) == nil && parseList(sender) == nil && parseList(titleText) == nil)
    }

    private func buildSource() -> Source {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegex = regex.trimmingCharacters(in: .whitespaces)
        let trimmedTarget = openTarget.trimmingCharacters(in: .whitespaces)
        return Source(
            name: name.trimmingCharacters(in: .whitespaces),
            match: SourceMatch(
                appBundleIds: parseList(bundleIDs),
                senderContains: parseList(sender),
                titleContains: parseList(titleText),
                bodyContains: parseList(bodyText)),
            otpRegex: trimmedRegex.isEmpty ? nil : trimmedRegex,
            actions: SourceActions(
                autoCopy: autoCopy,
                showActionableNotification: showBanner,
                openButton: openButton,
                openTarget: trimmedTarget.isEmpty ? nil : trimmedTarget,
                runCommand: trimmedCommand.isEmpty ? nil : trimmedCommand))
    }

    private func parseList(_ text: String) -> [String]? {
        let parts = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }
}

// MARK: - Settings tab

struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: ConfigModel
    @AppStorage("maskCodeInBanner") private var maskCodeInBanner = false
    @State private var regexDraft = ""

    private static let clearChoices: [(label: String, seconds: Int)] = [
        ("Never", 0), ("After 15 seconds", 15), ("After 30 seconds", 30),
        ("After 1 minute", 60), ("After 2 minutes", 120), ("After 5 minutes", 300),
    ]
    private static let pollChoices: [(label: String, seconds: Double)] = [
        ("Every 5 seconds", 5), ("Every 15 seconds", 15),
        ("Every 30 seconds", 30), ("Every minute", 60),
    ]

    var body: some View {
        Form {
            Section("Clipboard") {
                Picker("Clear copied codes from the clipboard", selection: clipboardClearBinding) {
                    ForEach(clearOptions, id: \.seconds) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
                Text("Codes are short-lived — clearing the clipboard keeps them away from other apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Privacy") {
                Toggle("Hide the code in Notiful’s banner", isOn: $maskCodeInBanner)
                Text("Shows “Telegram code received · Click to copy” instead of the code itself — keeps codes off the lock screen and out of Notification Center history.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Detection") {
                HStack {
                    TextField("Default code pattern (regex)", text: $regexDraft)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(applyRegex)
                    Button("Apply", action: applyRegex)
                        .disabled(regexDraft == model.config.defaultOTPRegex)
                    Button("Reset") {
                        regexDraft = Config.defaultRegex
                        applyRegex()
                    }
                    .disabled(model.config.defaultOTPRegex == Config.defaultRegex)
                }
                Text("Used as the fallback for sources without a custom pattern. Smart keyword detection runs first either way.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Advanced") {
                Picker("Fallback scan interval", selection: pollBinding) {
                    ForEach(pollOptions, id: \.seconds) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
                Text("Notifications are normally detected instantly via the file watcher — this timer is only a safety net. Sparser is easier on the battery.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    model.openRawConfig()
                } label: {
                    Label("Edit Raw Config File…", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { regexDraft = model.config.defaultOTPRegex }
    }

    private func applyRegex() {
        let trimmed = regexDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, (try? NSRegularExpression(pattern: trimmed)) != nil else {
            regexDraft = model.config.defaultOTPRegex  // invalid or empty — revert
            return
        }
        regexDraft = trimmed
        model.config.defaultOTPRegex = trimmed
        model.save()
    }

    // Include the current value as an extra option if it was hand-edited to something non-standard,
    // so the picker never silently shows the wrong state.
    private var clearOptions: [(label: String, seconds: Int)] {
        let current = model.config.clipboardAutoClearSeconds
        if Self.clearChoices.contains(where: { $0.seconds == current }) { return Self.clearChoices }
        return Self.clearChoices + [("After \(current) seconds (custom)", current)]
    }

    private var pollOptions: [(label: String, seconds: Double)] {
        let current = model.config.pollIntervalSeconds
        if Self.pollChoices.contains(where: { $0.seconds == current }) { return Self.pollChoices }
        return Self.pollChoices + [("Every \(Int(current)) seconds (custom)", current)]
    }

    private var clipboardClearBinding: Binding<Int> {
        Binding(
            get: { model.config.clipboardAutoClearSeconds },
            set: { model.config.clipboardAutoClearSeconds = $0; model.save() })
    }

    private var pollBinding: Binding<Double> {
        Binding(
            get: { model.config.pollIntervalSeconds },
            set: { model.config.pollIntervalSeconds = $0; model.save() })
    }
}

// MARK: - Small reusable pieces

/// A small colored capsule badge (e.g. "Auto-copy", "Command").
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundColor(color)
    }
}

/// Centered icon + title + message, used as an empty-state overlay.
struct EmptyHint: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .allowsHitTesting(false)
    }
}
