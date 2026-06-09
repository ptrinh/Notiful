import Foundation
import SQLite3

/// Reads the macOS Notification Center SQLite database safely.
///
/// We never touch the live DB directly: we copy `db`, `db-wal`, `db-shm` to a temp dir and open the
/// copy read-only. Copying the WAL is essential — freshly delivered notifications live there before
/// being checkpointed into the main file.
open class NotificationDatabase {
    public enum DBError: Error, CustomStringConvertible {
        case notFound
        case accessDenied(String)
        case openFailed(String)

        public var description: String {
            switch self {
            case .notFound: return "Notification database not found."
            case .accessDenied(let p): return "Access denied reading \(p). Grant Full Disk Access."
            case .openFailed(let m): return "Failed to open database copy: \(m)"
            }
        }
    }

    public let sourceURL: URL

    public init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    /// Locate the notification DB for this macOS version.
    public static func locate() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        // Sequoia (15) and later, incl. macOS 26.
        let modern = home.appendingPathComponent(
            "Library/Group Containers/group.com.apple.usernoted/db2/db")
        if fm.fileExists(atPath: modern.path) { return modern }

        // Older fallback: $(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db
        if let darwinUserDir = darwinUserDirectory() {
            let legacy = darwinUserDir
                .appendingPathComponent("com.apple.notificationcenter/db2/db")
            if fm.fileExists(atPath: legacy.path) { return legacy }
        }
        return nil
    }

    private static func darwinUserDirectory() -> URL? {
        let size = confstr(_CS_DARWIN_USER_DIR, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, size) > 0 else { return nil }
        let path = String(cString: buffer)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Modification time of the WAL (or the main DB) — a cheap stat used to skip redundant scans.
    /// Returns 0 if neither is statable.
    public func changeStamp() -> TimeInterval {
        let fm = FileManager.default
        let dir = sourceURL.deletingLastPathComponent()
        let base = sourceURL.lastPathComponent
        var newest: TimeInterval = 0
        for suffix in ["-wal", ""] {
            let p = dir.appendingPathComponent(base + suffix).path
            if let attrs = try? fm.attributesOfItem(atPath: p),
               let date = attrs[.modificationDate] as? Date {
                newest = max(newest, date.timeIntervalSinceReferenceDate)
            }
        }
        return newest
    }

    /// True if we can actually read the source file (Full Disk Access granted).
    public func canRead() -> Bool {
        guard let h = try? FileHandle(forReadingFrom: sourceURL) else { return false }
        try? h.close()
        return true
    }

    /// Fetch decoded records, optionally only those newer than a given rec_id and/or delivered_date.
    open func fetchRecords(afterRecID: Int64? = nil,
                           afterDate: Double? = nil,
                           limit: Int? = nil) throws -> [NotificationRecord] {
        let temp = try copyDatabase()
        defer { try? FileManager.default.removeItem(at: temp) }

        var db: OpaquePointer?
        let dbPath = temp.appendingPathComponent("db").path
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw DBError.openFailed(msg)
        }
        defer { sqlite3_close(db) }

        var sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE 1=1
            """
        if afterRecID != nil { sql += " AND r.rec_id > ?" }
        if afterDate != nil { sql += " AND r.delivered_date > ?" }
        sql += " ORDER BY r.delivered_date DESC, r.rec_id DESC"
        if let limit = limit { sql += " LIMIT \(limit)" }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        if let afterRecID = afterRecID {
            sqlite3_bind_int64(stmt, bindIndex, afterRecID); bindIndex += 1
        }
        if let afterDate = afterDate {
            sqlite3_bind_double(stmt, bindIndex, afterDate); bindIndex += 1
        }

        var records: [NotificationRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let recID = sqlite3_column_int64(stmt, 0)
            let bundleID = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let blobLen = Int(sqlite3_column_bytes(stmt, 2))
            let data = Data(bytes: blob, count: blobLen)
            let delivered = sqlite3_column_double(stmt, 3)
            if let rec = BPlistDecoder.decode(data: data, recID: recID, bundleID: bundleID, deliveredDate: delivered) {
                records.append(rec)
            }
        }
        return records
    }

    /// The newest record (by delivered_date) that matches one of the configured sources, with its source.
    public func latestMatching(sources: [Source], limit: Int = 50) throws -> (record: NotificationRecord, source: Source)? {
        let records = try fetchRecords(limit: limit)
        for rec in records {
            if let source = SourceMatcher.match(record: rec, sources: sources) {
                return (rec, source)
            }
        }
        return nil
    }

    // MARK: - Safe copy

    private func copyDatabase() throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { throw DBError.notFound }
        guard canRead() else { throw DBError.accessDenied(sourceURL.path) }

        let temp = fm.temporaryDirectory.appendingPathComponent("notiful-db-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)

        let dir = sourceURL.deletingLastPathComponent()
        let base = sourceURL.lastPathComponent  // "db"
        for suffix in ["", "-wal", "-shm"] {
            let src = dir.appendingPathComponent(base + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = temp.appendingPathComponent(base + suffix)
            // Remove any stale copy then copy fresh.
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
        return temp
    }
}
