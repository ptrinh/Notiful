import Foundation
import NotifulCore

/// Runs a user-configured shell command when a code is detected.
///
/// The notification text and code are passed as ENVIRONMENT VARIABLES rather than interpolated into
/// the command string — this avoids shell-injection from notification content. The command runs
/// asynchronously and never blocks detection.
///
///   Available env vars: NOTIFUL_CODE, NOTIFUL_SOURCE, NOTIFUL_APP,
///                       NOTIFUL_TITLE, NOTIFUL_SUBTITLE, NOTIFUL_BODY
///
/// Example command:  echo "$NOTIFUL_SOURCE code arrived" | terminal-notifier ...
enum CommandRunner {
    static func run(_ command: String, detection: DetectedCode) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        var env = ProcessInfo.processInfo.environment
        env["NOTIFUL_CODE"] = detection.code
        env["NOTIFUL_SOURCE"] = detection.source.name
        env["NOTIFUL_APP"] = detection.record.bundleID
        env["NOTIFUL_TITLE"] = detection.record.title
        env["NOTIFUL_SUBTITLE"] = detection.record.subtitle
        env["NOTIFUL_BODY"] = detection.record.body
        process.environment = env

        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                NotifulLog.error("runCommand for \(detection.source.name) exited \(proc.terminationStatus)")
            }
        }

        do {
            try process.run()
            NotifulLog.info("Ran command for \(detection.source.name) (code \(NotifulLog.mask(detection.code)))")
        } catch {
            NotifulLog.error("runCommand failed to launch: \(error)")
        }
    }
}
