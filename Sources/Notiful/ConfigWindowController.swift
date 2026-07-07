import AppKit
import SwiftUI
import NotifulCore

/// Hosts the SwiftUI settings UI (ConfigView) in a plain NSWindow — the app is a menu-bar
/// NSApplicationDelegate app with no scenes. Public API is unchanged from the old AppKit version.
final class ConfigWindowController: NSObject {
    private let window: NSWindow
    private let model: ConfigModel

    init(database: NotificationDatabase?, current: Config,
         onSave: @escaping (Config) -> Void,
         onTest: @escaping (NotificationRecord) -> Bool) {
        model = ConfigModel(database: database, config: current, onSave: onSave, onTest: onTest)
        let hosting = NSHostingController(rootView: ConfigView().environmentObject(model))
        window = NSWindow(contentViewController: hosting)
        window.title = "Notiful — Sources & Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 640))
        window.center()
        window.isReleasedWhenClosed = false
        super.init()
    }

    func refresh(current: Config) {
        model.config = current
        model.reloadRecent()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.reloadRecent()
    }
}

/// Observable bridge between the SwiftUI views and the rest of the app (config persistence,
/// notification DB reads). All DB fetches happen off the main thread.
final class ConfigModel: ObservableObject {
    @Published var config: Config
    @Published var recent: [RecentRow] = []
    @Published var canReadDB = true

    struct RecentRow: Identifiable, Equatable {
        let id: Int64
        let record: NotificationRecord
    }

    private let database: NotificationDatabase?
    private let onSave: (Config) -> Void
    private let onTest: (NotificationRecord) -> Bool
    private let fetchQueue = DispatchQueue(label: "com.notiful.config-fetch", qos: .userInitiated)
    private let ownBundleID = (Bundle.main.bundleIdentifier ?? "com.notiful.app").lowercased()
    private var appNameCache: [String: String] = [:]

    init(database: NotificationDatabase?, config: Config,
         onSave: @escaping (Config) -> Void,
         onTest: @escaping (NotificationRecord) -> Bool) {
        self.database = database
        self.config = config
        self.onSave = onSave
        self.onTest = onTest
    }

    /// Persist the current config and notify the app (recreates the scanner).
    func save() {
        onSave(config)
    }

    func reloadRecent() {
        guard let db = database else {
            canReadDB = false; recent = []
            return
        }
        fetchQueue.async { [weak self] in
            guard let self = self else { return }
            let canRead = db.canRead()
            var rows: [RecentRow] = []
            if canRead {
                let own = self.ownBundleID
                rows = ((try? db.fetchRecords(limit: 60)) ?? [])
                    .filter { $0.bundleID.lowercased() != own }  // hide our own notifications
                    .map { RecentRow(id: $0.recID, record: $0) }
            }
            DispatchQueue.main.async {
                self.canReadDB = canRead
                self.recent = rows
            }
        }
    }

    // MARK: - Mutations

    func addByApp(_ record: NotificationRecord) {
        config.sources.append(Source(name: appName(record.bundleID),
                                     match: SourceMatch(appBundleIds: [record.bundleID])))
        save()
    }

    func append(_ source: Source) {
        config.sources.append(source)
        save()
    }

    func update(_ source: Source, at index: Int) {
        guard config.sources.indices.contains(index) else { return }
        config.sources[index] = source
        save()
    }

    func removeSource(at index: Int) {
        guard config.sources.indices.contains(index) else { return }
        config.sources.remove(at: index)
        save()
    }

    // MARK: - Display helpers

    func matches(_ record: NotificationRecord) -> Bool {
        SourceMatcher.match(record: record, sources: config.sources) != nil
    }

    /// Replay a watched notification through the real capture pipeline (banner + auto-copy + command),
    /// exactly as if it had just arrived. Returns true if a code was detected and acted on.
    func test(_ record: NotificationRecord) -> Bool {
        onTest(record)
    }

    func appName(_ bundleID: String) -> String {
        if let cached = appNameCache[bundleID] { return cached }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            name = bundleID
        }
        appNameCache[bundleID] = name
        return name
    }

    func matchSummary(_ m: SourceMatch) -> String {
        var parts: [String] = []
        if let a = m.appBundleIds, !a.isEmpty {
            parts.append("App is \(a.map(appName).joined(separator: " or "))")
        }
        if let s = m.senderContains, !s.isEmpty { parts.append("Sender contains “\(s.joined(separator: "” or “"))”") }
        if let t = m.titleContains, !t.isEmpty { parts.append("Title contains “\(t.joined(separator: "” or “"))”") }
        if let b = m.bodyContains, !b.isEmpty { parts.append("Body contains “\(b.joined(separator: "” or “"))”") }
        return parts.isEmpty ? "Matches nothing — edit to add criteria" : parts.joined(separator: " · ")
    }

    func openRawConfig() {
        _ = ConfigStore.loadOrCreate()
        NSWorkspace.shared.open(ConfigStore.configURL)
    }
}
