import AppKit
import UserNotifications
import ServiceManagement
import NotifulCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var watcher: Watcher?
    private var scanner: NotifulScanner?
    private var database: NotificationDatabase?
    private var config = Config()
    private let state = StateStore()
    private let launchDate = Date().timeIntervalSinceReferenceDate
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.notiful.app"

    private var enabled = true
    /// Whether macOS currently lets Notiful post notifications (re-checked on launch / activate).
    private var notificationsAuthorized = true
    private var bannerWatcher: BannerWatcher?
    /// Codes acted on recently (in memory), to de-dupe the instant Accessibility path against the
    /// slower database path so the same code isn't handled twice.
    private var recentlyActed: [(code: String, at: Date)] = []
    /// Codes we acted on this session (newest first, capped), so a missed banner is recoverable
    /// straight from the menu: "Copy last code" + a Recent Codes submenu.
    private var recentCodes: [(code: String, source: String, at: Date)] = []
    private let recentCodesCap = 5

    private let categoryID = "NOTIFUL_OTP"
    private let copyAction = "COPY"
    private let openAction = "OPEN"
    private let codeKey = "code"
    private let openTargetKey = "openTarget"

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = ConfigStore.loadOrCreate()
        setupStatusItem()
        setupNotifications()

        // First-run explainer (what it is + why it needs Full Disk Access).
        Welcome.showIfNeeded()

        guard let dbURL = NotificationDatabase.locate() else {
            NotifulLog.error("Notification database not found.")
            updateStatusIcon(ok: false)
            return
        }
        let db = NotificationDatabase(sourceURL: dbURL)
        self.database = db
        guard db.canRead() else {
            FDA.printInstructions()
            updateStatusIcon(ok: false)
            notifyFDARequired()
            startFDARetryTimer()  // auto-start the moment access is granted — no relaunch needed
            return
        }
        finishStartup(db: db)
    }

    /// Everything that needs Full Disk Access — called at launch, or later by the retry timer the
    /// moment the user grants access in System Settings.
    private func finishStartup(db: NotificationDatabase) {
        scanner = NotifulScanner(database: db, config: config, state: state, launchDate: launchDate, excludeBundleIDs: [ownBundleID])
        startWatching(dbURL: db.sourceURL)
        tryStartBannerWatcher()
        updateStatusIcon(ok: true)
        rebuildMenu()
        NotifulLog.info("Notiful started. Watching \(config.sources.count) source(s).")
    }

    // MARK: - Full Disk Access recovery

    private var fdaRetryTimer: DispatchSourceTimer?

    /// Poll for Full Disk Access while it's missing. Previously the app silently required a manual
    /// relaunch after granting; now it springs to life by itself within a few seconds.
    private func startFDARetryTimer() {
        guard fdaRetryTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 3, repeating: 3, leeway: .seconds(1))
        t.setEventHandler { [weak self] in
            guard let self = self, let db = self.database, db.canRead() else { return }
            self.fdaRetryTimer?.cancel()
            self.fdaRetryTimer = nil
            self.finishStartup(db: db)
            NotifulLog.info("Full Disk Access granted — watching started without relaunch.")
            // Swap the "needs access" notification for a ready confirmation.
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: ["fda"])
            let content = UNMutableNotificationContent()
            content.title = "Notiful is ready"
            content.body = "Full Disk Access granted — now watching for codes."
            center.add(UNNotificationRequest(identifier: "fda-ok", content: content, trigger: nil),
                       withCompletionHandler: nil)
        }
        fdaRetryTimer = t
        t.resume()
    }

    private func startWatching(dbURL: URL) {
        watcher = Watcher(databaseURL: dbURL, interval: config.pollIntervalSeconds) { [weak self] in
            self?.scan()
        }
        watcher?.start()
        scan()  // initial pass
    }

    // MARK: - Scanning

    /// Serial queue for all DB work (copy + SQLite + bplist decoding). Keeping it off the main
    /// thread means the menu and config window can never stall behind a multi-MB DB copy.
    /// The scanner and its StateStore are only ever touched from this queue.
    private let scanQueue = DispatchQueue(label: "com.notiful.scan", qos: .utility)
    /// Accessed on scanQueue only.
    private var lastChangeStamp: TimeInterval = 0

    private func scan() {
        guard enabled, let scanner = scanner, let db = database else { return }
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            // Cheap guard: if the DB/WAL hasn't changed since our last scan, skip the copy+query
            // entirely. This makes idle timer ticks cost only a stat() instead of copying the DB.
            let stamp = db.changeStamp()
            if stamp != 0 && stamp == self.lastChangeStamp { return }
            do {
                let detections = try scanner.scanNew()
                // Only advance the stamp once the scan succeeded, so a transient copy/open failure
                // is retried on the next tick instead of waiting for the next DB change.
                self.lastChangeStamp = stamp
                guard !detections.isEmpty else { return }
                DispatchQueue.main.async {
                    for d in detections { self.handle(d) }
                }
            } catch {
                NotifulLog.error("scan failed: \(error)")
            }
        }
    }

    /// Acts on a detection. Returns false (no-op) if this code was already handled recently — this is
    /// what keeps the instant Accessibility path and the slower DB path from double-acting.
    @discardableResult
    private func handle(_ detection: DetectedCode, via: String = "database (~5s delay)") -> Bool {
        guard !actedRecently(detection.code) else { return false }
        NotifulLog.event("Captured \(detection.source.name) code \(NotifulLog.mask(detection.code)) — \(via)")
        recentCodes.insert((detection.code, detection.source.name, Date()), at: 0)
        if recentCodes.count > recentCodesCap { recentCodes.removeLast() }

        let actions = detection.source.actions
        if actions.autoCopy {
            Clipboard.copy(detection.code)
            scheduleAutoClear(detection.code)
        }
        if actions.showActionableNotification {
            postNotification(for: detection)
        }
        if let command = actions.runCommand, !command.isEmpty {
            CommandRunner.run(command, detection: detection)
        }
        return true
    }

    /// True if this exact code was acted on in the last 2 minutes (and records it if not).
    private func actedRecently(_ code: String) -> Bool {
        let now = Date()
        recentlyActed.removeAll { now.timeIntervalSince($0.at) > 120 }
        if recentlyActed.contains(where: { $0.code == code }) { return true }
        recentlyActed.append((code, now))
        return false
    }

    // MARK: - Instant capture (Accessibility banner reader)

    private var bannerHealthTimer: DispatchSourceTimer?

    /// Start the banner watcher if the user enabled instant capture. If Accessibility isn't granted
    /// yet (or NotificationCenter isn't found), retry periodically until it succeeds. Also (re)arms
    /// if the banner-host process restarted.
    private func tryStartBannerWatcher() {
        guard Preferences.instantCapture else { return }
        startBannerHealthTimer()
        if bannerWatcher?.needsReArm() == false { return }

        if bannerWatcher == nil {
            bannerWatcher = BannerWatcher { [weak self] texts, dismiss in
                self?.handleBanner(texts: texts, dismiss: dismiss)
            }
        }
        if bannerWatcher?.start() != true {
            // Not trusted yet (or host not found) — retry while still enabled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self = self, Preferences.instantCapture else { return }
                self.tryStartBannerWatcher()
            }
        }
    }

    /// Self-heal independently of the menu: even with the menu-bar icon hidden, periodically ensure
    /// the watcher is armed and re-arm it if the NotificationCenter process restarted.
    private func startBannerHealthTimer() {
        guard bannerHealthTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        // Sparse + loose-leeway: this only recovers from a NotificationCenter restart, so it doesn't
        // need to be punctual. Large leeway lets the OS coalesce the wakeup for better battery.
        t.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(10))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard Preferences.instantCapture else { return }
            if self.bannerWatcher?.needsReArm() != false { self.tryStartBannerWatcher() }
        }
        bannerHealthTimer = t
        t.resume()
    }

    private func stopBannerWatcher() {
        bannerWatcher?.stop()
        bannerWatcher = nil
        bannerHealthTimer?.cancel()
        bannerHealthTimer = nil
    }

    private func handleBanner(texts: [String], dismiss: @escaping () -> Void) {
        guard enabled else { return }
        let joined = texts.joined(separator: "\n")
        // Ignore our own banner (the system shows "Notiful" as its app label) to avoid a loop.
        if texts.contains(where: { $0 == "Notiful" }) || joined.contains("Notiful · ") { return }

        // The banner doesn't expose the posting app's bundle id, so match on the displayed text.
        // (Native-app-by-bundle-id sources are still covered by the database fallback.)
        let record = NotificationRecord(recID: -1, bundleID: "", title: joined, subtitle: "",
                                        body: joined, deliveredDate: Date().timeIntervalSinceReferenceDate)
        guard let source = SourceMatcher.match(record: record, sources: config.sources) else { return }

        let code: String?
        if let custom = source.otpRegex {
            code = OTPExtractor.extract(record: record, regex: custom)
        } else {
            code = OTPExtractor.extract(record: record, regex: nil)
                ?? OTPExtractor.extract(record: record, regex: config.defaultOTPRegex)
        }
        guard let code = code, !code.isEmpty else { return }

        let detection = DetectedCode(code: code, source: source, record: record)
        let acted = handle(detection, via: "INSTANT (Accessibility)")
        if acted, Preferences.autoDismissSourceBanner { dismiss() }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Clear any of our own previously-delivered notifications (e.g. the old feedback-loop backlog).
        center.removeAllDeliveredNotifications()

        let copy = UNNotificationAction(identifier: copyAction, title: "Copy", options: [])
        let open = UNNotificationAction(identifier: openAction, title: "Open Source", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [copy, open],
            intentIdentifiers: [],
            options: [.customDismissAction])
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { NotifulLog.error("notification auth: \(error)") }
            if !granted { NotifulLog.error("Notification permission not granted — codes will still be copyable from the menu.") }
        }
        refreshNotificationAuth()
    }

    /// Re-check whether macOS still lets us post notifications. getNotificationSettings is the source of
    /// truth (the requestAuthorization `granted` flag is unreliable for ad-hoc-signed/rebuilt apps).
    /// We only warn on a DEFINITIVE denial — never on .notDetermined — to avoid false positives.
    private func refreshNotificationAuth() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let ok = settings.authorizationStatus != .denied
            DispatchQueue.main.async {
                if self?.notificationsAuthorized != ok { self?.notificationsAuthorized = ok; self?.rebuildMenu() }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshNotificationAuth()
    }

    private func postNotification(for detection: DetectedCode) {
        guard Preferences.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        if Preferences.maskCodeInBanner {
            // Keep the code itself off the lock screen / Notification Center history.
            content.title = "\(detection.source.name) code received"
        } else {
            content.title = "\(detection.source.name) · \(detection.code)"
        }
        content.body = "Click to copy"
        content.categoryIdentifier = categoryID
        var info: [String: Any] = [codeKey: detection.code]
        if detection.source.actions.openButton, let target = detection.source.actions.openTarget {
            info[openTargetKey] = target
        }
        content.userInfo = info

        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.add(request) { error in
            if let error = error { NotifulLog.error("post notification: \(error)") }
        }
        // OTPs are short-lived; don't leave them sitting in Notification Center history.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    private func notifyFDARequired() {
        let content = UNMutableNotificationContent()
        content.title = "Notiful needs Full Disk Access"
        content.body = "Click to open Privacy & Security settings."
        content.userInfo = ["fda": true]
        let request = UNNotificationRequest(identifier: "fda", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // UNUserNotificationCenterDelegate — show our banner even when app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle clicks and action buttons.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if info["fda"] != nil {
            FDA.openSettings()
            completionHandler(); return
        }
        guard let code = info[codeKey] as? String else { completionHandler(); return }

        switch response.actionIdentifier {
        case openAction:
            if let target = info[openTargetKey] as? String { openTarget(target) }
        case copyAction, UNNotificationDefaultActionIdentifier:
            Clipboard.copy(code)
            scheduleAutoClear(code)
            NotifulLog.info("Copied code to clipboard via notification")
        default:
            break
        }
        completionHandler()
    }

    private func openTarget(_ target: String) {
        if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Clipboard auto-clear

    private func scheduleAutoClear(_ code: String) {
        let seconds = config.clipboardAutoClearSeconds
        guard seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds)) {
            Clipboard.clearIfStillHolds(code)
        }
    }

    // MARK: - Status item / menu

    private var statusOK = true

    private func setupStatusItem() {
        guard !Preferences.hideMenuBarIcon else { return }  // start hidden if the user chose that
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(ok: statusOK)
        rebuildMenu()
    }

    private func updateStatusIcon(ok: Bool) {
        statusOK = ok
        if let button = statusItem?.button {
            let name = ok ? "key.fill" : "exclamationmark.triangle.fill"
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Notiful")
        }
    }

    private func hideMenuBarIcon() {
        Preferences.hideMenuBarIcon = true
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func showMenuBarIcon() {
        Preferences.hideMenuBarIcon = false
        if statusItem == nil { setupStatusItem() }
    }

    // Re-launching the app (e.g. double-clicking it in Finder) re-shows a hidden icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if Preferences.hideMenuBarIcon { showMenuBarIcon() }
        return true
    }

    private let menu = NSMenu()

    private func rebuildMenu() {
        populateMenu(menu)
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Health warnings at the very top, only when something is actually broken.
        if Preferences.notificationsEnabled && !notificationsAuthorized {
            let w = NSMenuItem(title: "⚠️ Banners are turned off in macOS — open Settings",
                               action: #selector(openNotificationSettings), keyEquivalent: "")
            w.target = self
            menu.addItem(w)
            menu.addItem(.separator())
        }
        // Instant capture is on but Accessibility isn't granted (e.g. revoked by an app update) —
        // codes silently fall back to the ~5s database path, so surface it.
        if Preferences.instantCapture && !Accessibility.isTrusted() {
            let w = NSMenuItem(title: "⚠️ Instant capture needs Accessibility — open Settings",
                               action: #selector(openAccessibilitySettings), keyEquivalent: "")
            w.target = self
            menu.addItem(w)
            menu.addItem(.separator())
        }

        // Status header (non-clickable): what Notiful is doing right now.
        addStatusHeader(menu)
        menu.addItem(.separator())

        // Captured codes — recoverable even if the banner was missed.
        if let last = recentCodes.first {
            let copy = NSMenuItem(title: "Copy Last Code — \(last.code) (\(last.source))",
                                  action: #selector(copyRecentCode(_:)), keyEquivalent: "c")
            copy.target = self
            copy.representedObject = last.code
            copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copy)

            if recentCodes.count > 1 {
                let recentItem = NSMenuItem(title: "Recent Codes", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for entry in recentCodes {
                    let item = NSMenuItem(title: "\(entry.code) — \(entry.source) · \(Self.relativeTime(since: entry.at))",
                                          action: #selector(copyRecentCode(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = entry.code
                    sub.addItem(item)
                }
                recentItem.submenu = sub
                menu.addItem(recentItem)
            }
            menu.addItem(.separator())
        }

        // Primary on/off, with an explicit object so it's never an ambiguous bare verb.
        let toggle = NSMenuItem(title: enabled ? "Pause watching" : "Resume watching",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        // --- Settings group ---
        menu.addItem(sectionHeader("Settings"))

        let notif = NSMenuItem(title: "Show a banner when a code is found", action: #selector(toggleNotifications), keyEquivalent: "")
        notif.target = self
        notif.state = Preferences.notificationsEnabled ? .on : .off
        menu.addItem(notif)

        let instant = NSMenuItem(title: "Instant capture (read banners as they appear)", action: #selector(toggleInstantCapture), keyEquivalent: "")
        instant.target = self
        instant.state = Preferences.instantCapture ? .on : .off
        menu.addItem(instant)

        if Preferences.instantCapture {
            let dismiss = NSMenuItem(title: "Auto-hide the original banner after capture", action: #selector(toggleAutoDismiss), keyEquivalent: "")
            dismiss.target = self
            dismiss.indentationLevel = 1
            dismiss.state = Preferences.autoDismissSourceBanner ? .on : .off
            menu.addItem(dismiss)
        }

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = isLoginEnabled() ? .on : .off
        menu.addItem(login)

        addItem(menu, "Sources & Settings…", #selector(openConfigUI), key: ",")
        menu.addItem(.separator())

        // --- Troubleshooting group ---
        addItem(menu, "Open Notiful’s log…", #selector(openLog))
        // Only show the grant shortcut while access is still missing.
        if !FDA.isGranted() {
            addItem(menu, "Grant Full Disk Access…", #selector(grantFDA))
        }
        addItem(menu, "Hide menu bar icon…", #selector(hideIcon))
        menu.addItem(.separator())

        addItem(menu, "Donate ♥…", #selector(donate))
        addItem(menu, "About Notiful", #selector(showCredit))
        addItem(menu, "Quit Notiful", #selector(quit), key: "q")
    }

    /// Non-clickable header(s) describing current state: paused/watching, source count, last capture.
    private func addStatusHeader(_ menu: NSMenu) {
        let count = config.sources.count
        let state = enabled
            ? "Watching \(count) source\(count == 1 ? "" : "s")"
            : "Paused"
        menu.addItem(disabledItem(enabled ? "● \(state)" : "⏸ \(state)"))

        if let last = recentCodes.first {
            menu.addItem(disabledItem("Last code: \(last.source) · \(Self.relativeTime(since: last.at))", indent: 1))
        }
    }

    /// A bold, greyed-out section label.
    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    private func disabledItem(_ title: String, indent: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent
        return item
    }

    private static func relativeTime(since date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        switch secs {
        case ..<10: return "just now"
        case ..<60: return "\(secs)s ago"
        case ..<3600: return "\(secs / 60)m ago"
        case ..<86400: return "\(secs / 3600)h ago"
        default: return "\(secs / 86400)d ago"
        }
    }

    // Re-check notification permission each time the menu opens, so the warning is always current.
    // Also re-arm the banner watcher in case the NotificationCenter process was restarted.
    // Repopulate the same menu instance just before it's shown, so the status header (source count,
    // last capture) and toggle states are always live without swapping the menu out from under AppKit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshNotificationAuth()
        if Preferences.instantCapture, bannerWatcher?.isRunning != true { tryStartBannerWatcher() }
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func copyRecentCode(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        Clipboard.copy(code)
        scheduleAutoClear(code)
        NotifulLog.info("Copied a recent code from the menu")
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        NotifulLog.info(enabled ? "Enabled" : "Disabled")
        rebuildMenu()
        if enabled { scan() }
    }

    @objc private func toggleNotifications() {
        Preferences.notificationsEnabled.toggle()
        NotifulLog.info("Notiful notifications \(Preferences.notificationsEnabled ? "on" : "off")")
        rebuildMenu()
    }

    @objc private func openLog() {
        // Console can't be opened pre-filtered to our subsystem, which left users in an unfiltered
        // firehose. Instead export just Notiful's recent log lines to a text file and open that.
        // `log show` takes several seconds, so post a progress notification — without it the menu
        // item looks like it did nothing.
        let progressID = "log-progress"
        let center = UNUserNotificationCenter.current()
        let progress = UNMutableNotificationContent()
        progress.title = "Collecting Notiful’s log…"
        progress.body = "This takes a few seconds — the log will open automatically."
        center.add(UNNotificationRequest(identifier: progressID, content: progress, trigger: nil),
                   withCompletionHandler: nil)

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("Notiful-log.txt")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["show", "--predicate", "subsystem == \"com.notiful.app\"",
                          "--last", "6h", "--info", "--style", "compact"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let body = data.isEmpty ? "No Notiful log entries in the last 6 hours." : String(decoding: data, as: UTF8.self)
            let header = "Notiful log — last 6 hours\n\n"
            try? (header + body).data(using: .utf8)?.write(to: out)
            DispatchQueue.main.async {
                center.removeDeliveredNotifications(withIdentifiers: [progressID])
                NSWorkspace.shared.open(out)
            }
        }
        do { try task.run() } catch {
            NotifulLog.error("open log: \(error)")
            center.removeDeliveredNotifications(withIdentifiers: [progressID])
        }
    }

    @objc private func hideIcon() {
        let confirm = NSAlert()
        confirm.messageText = "Hide the menu bar icon?"
        confirm.informativeText = "This is how you reach Notiful’s menu. With it hidden, Notiful keeps "
            + "running in the background — to bring the icon back, open Notiful from Applications or Spotlight."
        confirm.addButton(withTitle: "Hide Icon")
        confirm.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        hideMenuBarIcon()
    }

    @objc private func toggleInstantCapture() {
        Preferences.instantCapture.toggle()
        if Preferences.instantCapture {
            if !Accessibility.isTrusted() {
                Accessibility.requestTrust()
                let alert = NSAlert()
                alert.messageText = "Enable Accessibility for instant capture"
                alert.informativeText = """
                Instant capture reads the on-screen notification banner the moment it appears, so codes \
                are copied immediately instead of after the ~5s database delay.

                In System Settings → Privacy & Security → Accessibility, turn ON Notiful. It starts \
                working automatically once granted — no relaunch needed.

                Note: the source app's banner must stay visible (don't hide its "Desktop" banner) so \
                there's something to read. Enable "Auto-dismiss source banner" to clear it right after.
                """
                alert.addButton(withTitle: "Open Accessibility Settings")
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { Accessibility.openSettings() }
            }
            tryStartBannerWatcher()
        } else {
            stopBannerWatcher()
        }
        rebuildMenu()
    }

    @objc private func toggleAutoDismiss() {
        Preferences.autoDismissSourceBanner.toggle()
        rebuildMenu()
    }

    @objc private func grantFDA() { FDA.openSettings() }

    @objc private func openAccessibilitySettings() { Accessibility.openSettings() }

    @objc private func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showCredit() { Welcome.showIfNeeded(force: true) }

    @objc private func donate() { NSWorkspace.shared.open(Welcome.donationURL) }

    private var configWindow: ConfigWindowController?

    @objc private func openConfigUI() {
        if configWindow == nil {
            configWindow = ConfigWindowController(database: database, current: config) { [weak self] newConfig in
                self?.applyConfig(newConfig)
            }
        }
        configWindow?.refresh(current: config)
        configWindow?.show()
    }

    private func applyConfig(_ newConfig: Config) {
        let pollChanged = newConfig.pollIntervalSeconds != config.pollIntervalSeconds
        config = newConfig
        ConfigStore.save(newConfig)
        if let db = database, db.canRead() {
            scanner = NotifulScanner(database: db, config: config, state: state, launchDate: launchDate, excludeBundleIDs: [ownBundleID])
            if pollChanged {  // restart the watcher so the new interval applies without relaunch
                watcher?.stop()
                startWatching(dbURL: db.sourceURL)
            }
        }
        NotifulLog.info("Config updated: \(config.sources.count) source(s)")
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: - Login item (SMAppService)

    private func isLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NotifulLog.error("login item toggle failed: \(error)")
        }
        rebuildMenu()
    }
}
