import Foundation
import NotifulCore

// Headless `--once` mode: scan the latest matching notification, print + copy the code, then exit.
// This path does NOT require notification permission, so it's ideal for scripted testing.
if CommandLine.arguments.contains("--once") {
    OnceMode.run()
    exit(0)
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    Notiful — macOS notification OTP extractor

    Usage:
      Notiful            Run as a menu-bar app (default).
      Notiful --once     Scan the latest matching OTP notification, copy it, print masked result.
      Notiful --help     Show this help.
    """)
    exit(0)
}

// Normal mode: launch the menu-bar app.
import AppKit
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // LSUIElement-style: no Dock icon.
app.run()
