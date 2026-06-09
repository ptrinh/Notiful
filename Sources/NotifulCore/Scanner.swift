import Foundation

/// A code detected in a matching notification, ready to be acted upon.
public struct DetectedCode: Equatable, Sendable {
    public let code: String
    public let source: Source
    public let record: NotificationRecord
    public init(code: String, source: Source, record: NotificationRecord) {
        self.code = code
        self.source = source
        self.record = record
    }
}

/// Ties the DB reader, matcher, extractor and de-dupe together.
public final class NotifulScanner {
    private let database: NotificationDatabase
    private let config: Config
    private let state: StateStore?
    /// Records delivered before this time (Mac absolute) are ignored — set to launch time so we never
    /// act on stale notifications from before the app started.
    private let launchDate: Double
    /// Bundle ids to never act on — crucially our OWN, so Notiful's notifications don't re-trigger it.
    private let excludeBundleIDs: Set<String>

    public init(database: NotificationDatabase, config: Config, state: StateStore? = nil,
                launchDate: Double = 0, excludeBundleIDs: Set<String> = []) {
        self.database = database
        self.config = config
        self.state = state
        self.launchDate = launchDate
        self.excludeBundleIDs = Set(excludeBundleIDs.map { $0.lowercased() })
    }

    /// Scan for NEW matching codes (newer than the watermark and launch time). De-dupes via StateStore.
    /// Returns detections oldest-first and advances the watermark.
    public func scanNew(limit: Int = 30) throws -> [DetectedCode] {
        // Filter in SQL by the watermark so we only DECODE genuinely new records — on an idle/fallback
        // scan this returns 0 rows instead of decoding the newest `limit` bplists every time.
        let after = state.map { $0.state.lastRecID }
        let records = try database.fetchRecords(afterRecID: after, limit: limit)  // newest-first
        var detections: [DetectedCode] = []
        for rec in records.reversed() {  // process oldest-first so watermark advances correctly
            if rec.deliveredDate < launchDate { continue }
            if let state = state, state.isProcessed(recID: rec.recID) { continue }
            if let detection = detect(in: rec) {
                detections.append(detection)
            }
            // Advance watermark for every processed record (matched or not) to avoid re-scanning.
            state?.markProcessed(recID: rec.recID, deliveredDate: rec.deliveredDate)
        }
        return detections
    }

    /// One-shot: the newest matching code regardless of watermark. For `--once` / scripted use.
    public func scanLatest(limit: Int = 50) throws -> DetectedCode? {
        let records = try database.fetchRecords(limit: limit)  // newest-first
        for rec in records {
            if let detection = detect(in: rec) {
                return detection
            }
        }
        return nil
    }

    private func detect(in rec: NotificationRecord) -> DetectedCode? {
        // Never act on our own notifications (would create an infinite feedback loop).
        if excludeBundleIDs.contains(rec.bundleID.lowercased()) { return nil }
        guard let source = SourceMatcher.match(record: rec, sources: config.sources) else { return nil }
        let regex = source.otpRegex ?? config.defaultOTPRegex
        // Try source/global regex first; if that is the simple default, fall back to smart extraction.
        let code: String?
        if let custom = source.otpRegex {
            code = OTPExtractor.extract(record: rec, regex: custom)
        } else {
            // Smart keyword-biased extraction (ignores the trivial default pattern in favour of scoring).
            code = OTPExtractor.extract(record: rec, regex: nil)
                ?? OTPExtractor.extract(record: rec, regex: regex)
        }
        guard let code = code, !code.isEmpty else { return nil }
        return DetectedCode(code: code, source: source, record: rec)
    }
}
