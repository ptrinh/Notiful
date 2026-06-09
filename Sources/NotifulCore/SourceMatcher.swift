import Foundation

public enum SourceMatcher {
    /// Returns the first source that matches the record, or nil.
    public static func match(record: NotificationRecord, sources: [Source]) -> Source? {
        sources.first { matches(record: record, source: $0) }
    }

    static func matches(record: NotificationRecord, source: Source) -> Bool {
        let m = source.match

        // ANY of the positive criteria must hit.
        var matchedPositive = false

        if let ids = m.appBundleIds, !ids.isEmpty {
            if ids.contains(where: { $0.caseInsensitiveCompare(record.bundleID) == .orderedSame }) {
                matchedPositive = true
            }
        }
        if !matchedPositive, let needles = m.senderContains, !needles.isEmpty {
            // Sender-identifying text can live in the title OR the subtitle. Google Voice, for
            // example, puts the phone number in the title and "voice.google.com" in the subtitle.
            if containsAny(record.title, needles) || containsAny(record.subtitle, needles) {
                matchedPositive = true
            }
        }
        if !matchedPositive, let needles = m.titleContains, !needles.isEmpty {
            if containsAny(record.title, needles) { matchedPositive = true }
        }

        // If no positive criteria were configured at all, the source can't match anything.
        let hasPositiveCriteria = (m.appBundleIds?.isEmpty == false)
            || (m.senderContains?.isEmpty == false)
            || (m.titleContains?.isEmpty == false)
        if !hasPositiveCriteria { return false }
        if !matchedPositive { return false }

        // bodyContains, if present, is an additional gate.
        if let bodyNeedles = m.bodyContains, !bodyNeedles.isEmpty {
            if !containsAny(record.body, bodyNeedles) { return false }
        }
        return true
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        let lower = haystack.lowercased()
        return needles.contains { !$0.isEmpty && lower.contains($0.lowercased()) }
    }
}
