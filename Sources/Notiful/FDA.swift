import AppKit
import NotifulCore

enum FDA {
    static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// True if we can actually read the notification database (i.e. Full Disk Access is granted).
    static func isGranted() -> Bool {
        guard let url = NotificationDatabase.locate() else { return false }
        return NotificationDatabase(sourceURL: url).canRead()
    }

    static func printInstructions() {
        NotifulLog.error("""
        Full Disk Access is required to read the Notification Center database.

        Grant it:
          1. Open System Settings → Privacy & Security → Full Disk Access
          2. Add and enable Notiful (the .app), then relaunch it.

        (When running the raw build during development, grant the access to your terminal instead.)
        """)
    }

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
