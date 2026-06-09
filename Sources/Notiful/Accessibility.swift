import AppKit
import ApplicationServices

/// Helpers for the Accessibility permission (separate from Full Disk Access). Required to read the
/// notification banner on screen the instant it appears.
enum Accessibility {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user (opens System Settings → Privacy & Security → Accessibility).
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
