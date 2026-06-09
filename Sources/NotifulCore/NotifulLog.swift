import Foundation
import os

/// Lightweight logger. Crucially, it MASKS OTP codes anywhere they might be printed.
public enum NotifulLog {
    private static let logger = Logger(subsystem: "com.notiful.app", category: "main")

    /// Mask a code for display: keep first/last char, dots in the middle. "318204" -> "3••••4".
    public static func mask(_ code: String) -> String {
        guard code.count > 2 else { return String(repeating: "•", count: code.count) }
        let first = code.first!
        let last = code.last!
        let dots = String(repeating: "•", count: code.count - 2)
        return "\(first)\(dots)\(last)"
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        print("[Notiful] \(message)")
    }

    /// Notable events (code detections, etc.) logged at `.notice` level so they PERSIST to the
    /// unified log and can be retrieved later with `log show` — unlike `.info`, which is memory-only.
    public static func event(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        print("[Notiful] \(message)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("[Notiful] ERROR: \(message)\n".utf8))
    }
}
