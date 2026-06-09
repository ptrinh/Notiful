import AppKit
import NotifulCore

enum Clipboard {
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    /// Clear the clipboard, but ONLY if it still holds exactly `expected` (don't clobber later copies).
    static func clearIfStillHolds(_ expected: String) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == expected {
            pb.clearContents()
            NotifulLog.info("Cleared clipboard (auto-clear timeout reached)")
        }
    }
}
