import Foundation

/// A decoded notification record from the Notification Center DB.
public struct NotificationRecord: Equatable, Sendable {
    public let recID: Int64
    /// Bundle id of the posting app (from the `app` table — authoritative).
    public let bundleID: String
    public let title: String
    public let subtitle: String
    public let body: String
    /// Mac absolute time (seconds since 2001-01-01). Convert with +978307200 for Unix.
    public let deliveredDate: Double

    public init(recID: Int64, bundleID: String, title: String, subtitle: String, body: String, deliveredDate: Double) {
        self.recID = recID
        self.bundleID = bundleID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.deliveredDate = deliveredDate
    }

    /// The text most likely to identify a sender — title is where SMS/Voice put the sender.
    public var sender: String { title }
}

/// Decodes the `data` BLOB (a binary plist) of a `record` row.
public enum BPlistDecoder {
    /// Parse a notification bplist blob into its title/subtitle/body.
    /// Layout (confirmed on macOS 26): top-level `app`; under `req`: `titl`, `subt`, `body`.
    public static func decode(data: Data, recID: Int64, bundleID: String, deliveredDate: Double) -> NotificationRecord? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        // `app` inside the plist may differ in casing from the `app` table; prefer the table value
        // passed in, but fall back to the plist value if the caller didn't supply one.
        let resolvedBundle = bundleID.isEmpty ? (dict["app"] as? String ?? "") : bundleID

        let req = dict["req"] as? [String: Any] ?? dict
        let title = (req["titl"] as? String) ?? ""
        let subtitle = (req["subt"] as? String) ?? ""
        let body = (req["body"] as? String) ?? ""

        // A record with no text at all is not actionable.
        if title.isEmpty && subtitle.isEmpty && body.isEmpty { return nil }

        return NotificationRecord(
            recID: recID,
            bundleID: resolvedBundle,
            title: title,
            subtitle: subtitle,
            body: body,
            deliveredDate: deliveredDate
        )
    }
}
