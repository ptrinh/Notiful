import AppKit
import ApplicationServices
import NotifulCore

/// C-compatible AXObserver callback. Must be a non-capturing function so it can be a C function
/// pointer; the BannerWatcher instance is passed through `refcon`.
private func bannerAXCallback(observer: AXObserver,
                              element: AXUIElement,
                              notification: CFString,
                              refcon: UnsafeMutableRawPointer?) {
    guard let refcon = refcon else { return }
    let watcher = Unmanaged<BannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.elementCreated(element)
}

/// Reads on-screen notification banners via the Accessibility API the instant they appear — far
/// faster than the database (macOS only persists notifications to disk ~5s later). The banner UI is
/// owned by the system "Notification Center" process; we observe it for newly created windows and
/// pull out their static text.
final class BannerWatcher {
    /// Called with the banner's static-text lines and a closure that dismisses that banner.
    private let onBanner: (_ texts: [String], _ dismiss: @escaping () -> Void) -> Void

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var pid: pid_t = 0

    private let bannerHostBundleID = "com.apple.notificationcenterui"

    init(onBanner: @escaping (_ texts: [String], _ dismiss: @escaping () -> Void) -> Void) {
        self.onBanner = onBanner
    }

    var isRunning: Bool { observer != nil }

    /// True if we need to (re)arm: not armed yet, or the banner-host process restarted under a new
    /// PID (which silently invalidates the existing AXObserver).
    func needsReArm() -> Bool {
        if observer == nil { return true }
        if let current = bannerHostPID(), current != pid { return true }
        return false
    }

    /// Returns true if the observer was armed. Requires Accessibility trust.
    @discardableResult
    func start() -> Bool {
        guard Accessibility.isTrusted() else { return false }
        guard let pid = bannerHostPID() else { return false }
        stop()

        self.pid = pid
        let app = AXUIElementCreateApplication(pid)
        self.appElement = app

        var obs: AXObserver?
        guard AXObserverCreate(pid, bannerAXCallback, &obs) == .success, let obs = obs else { return false }
        self.observer = obs

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Banners appear as new windows; some macOS builds report them as generic created elements.
        for note in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(obs, app, note as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        NotifulLog.info("BannerWatcher armed on \(bannerHostBundleID) (pid \(pid))")
        return true
    }

    func stop() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        appElement = nil
    }

    // MARK: - Event handling

    fileprivate func elementCreated(_ element: AXUIElement) {
        readBanner(element, attempt: 0)
    }

    /// Banner subtrees may populate a beat after creation, so retry briefly if empty.
    private func readBanner(_ element: AXUIElement, attempt: Int) {
        var texts: [String] = []
        collectStaticText(element, depth: 0, into: &texts)
        if texts.isEmpty {
            if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.readBanner(element, attempt: attempt + 1)
                }
            }
            return
        }
        onBanner(texts) { [weak self] in self?.dismiss(element) }
    }

    // MARK: - AX traversal

    private func collectStaticText(_ element: AXUIElement, depth: Int, into out: inout [String]) {
        if depth > 12 || out.count > 60 { return }
        if let role = stringAttr(element, kAXRoleAttribute), role == (kAXStaticTextRole as String) {
            if let value = stringAttr(element, kAXValueAttribute), !value.isEmpty {
                out.append(value)
            }
        }
        for child in childrenOf(element) {
            collectStaticText(child, depth: depth + 1, into: &out)
        }
    }

    /// Labels meaning Close/Clear/Dismiss across the locales macOS ships in — banner button labels
    /// are localized, so English-only matching silently broke auto-dismiss on non-English systems.
    private static let dismissLabels = [
        "close", "clear", "dismiss",          // en
        "đóng", "xóa",                        // vi
        "fermer", "effacer",                  // fr
        "schließen", "entfernen",             // de
        "cerrar", "borrar",                   // es
        "fechar", "limpar",                   // pt
        "chiudi", "cancella",                 // it
        "sluit", "wis",                       // nl
        "закрыть", "очистить",                // ru
        "閉じる", "消去",                       // ja
        "关闭", "清除", "關閉",                  // zh
        "닫기", "지우기",                       // ko
        "kapat", "temizle",                   // tr
        "tutup", "hapus",                     // id
        "ปิด", "ล้าง",                          // th
        "إغلاق", "مسح",                       // ar
    ]

    private func dismiss(_ element: AXUIElement) {
        // Best-effort: find a Close/Clear button in the banner and press it.
        var buttons: [AXUIElement] = []
        collectButtons(element, depth: 0, into: &buttons)

        // Prefer the structural close button (subrole is locale-independent).
        for b in buttons {
            if let subrole = stringAttr(b, kAXSubroleAttribute),
               subrole == (kAXCloseButtonSubrole as String) {
                AXUIElementPerformAction(b, kAXPressAction as CFString)
                return
            }
        }
        // Fall back to matching the (localized) label text.
        for b in buttons {
            let label = ((stringAttr(b, kAXDescriptionAttribute) ?? "")
                + " " + (stringAttr(b, kAXTitleAttribute) ?? "")).lowercased()
            if Self.dismissLabels.contains(where: { label.contains($0) }) {
                AXUIElementPerformAction(b, kAXPressAction as CFString)
                return
            }
        }
    }

    private func collectButtons(_ element: AXUIElement, depth: Int, into out: inout [AXUIElement]) {
        if depth > 12 || out.count > 40 { return }
        if let role = stringAttr(element, kAXRoleAttribute), role == (kAXButtonRole as String) {
            out.append(element)
        }
        for child in childrenOf(element) {
            collectButtons(child, depth: depth + 1, into: &out)
        }
    }

    // MARK: - AX helpers

    private func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func childrenOf(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func bannerHostPID() -> pid_t? {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == bannerHostBundleID {
            return app.processIdentifier
        }
        return nil
    }
}
