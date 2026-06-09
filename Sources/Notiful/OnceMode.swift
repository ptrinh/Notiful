import Foundation
import AppKit
import NotifulCore

enum OnceMode {
    static func run() {
        guard let dbURL = NotificationDatabase.locate() else {
            NotifulLog.error("Notification database not found for this macOS version.")
            exit(2)
        }
        let db = NotificationDatabase(sourceURL: dbURL)
        guard db.canRead() else {
            FDA.printInstructions()
            exit(3)
        }
        let config = ConfigStore.loadOrCreate()
        let scanner = NotifulScanner(database: db, config: config)
        do {
            guard let detection = try scanner.scanLatest() else {
                print("No matching OTP notification found.")
                exit(1)
            }
            // Copy to clipboard.
            Clipboard.copy(detection.code)
            print("\(detection.source.name) · \(NotifulLog.mask(detection.code)) — copied to clipboard")
        } catch {
            NotifulLog.error("\(error)")
            exit(4)
        }
    }
}
