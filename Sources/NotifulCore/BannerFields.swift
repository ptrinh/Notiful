import Foundation

/// Assembles a banner's accessibility text lines into notification fields.
///
/// macOS tags each banner static-text element with an accessibility identifier — "title",
/// "subtitle", "body" (verified on macOS 15; see BannerWatcher). Using them lets the instant-capture
/// path scan the body only, like the database path, so a short-code SMS sender in the title
/// (e.g. "46939") is never mistaken for an OTP. When no line is tagged "body" (older macOS or a
/// layout change), we fall back to joining everything, which is the pre-identifier behavior.
public enum BannerFields {
    public struct Line {
        public let identifier: String?
        public let value: String
        public init(identifier: String?, value: String) {
            self.identifier = identifier
            self.value = value
        }
    }

    public struct Fields {
        public let title: String
        public let subtitle: String
        public let body: String
    }

    public static func assemble(_ lines: [Line]) -> Fields {
        let title = joined(lines, tagged: "title")
        let subtitle = joined(lines, tagged: "subtitle")
        let body = joined(lines, tagged: "body")
        guard !body.isEmpty else {
            // No tagged body — join every line so nothing is lost (matching and extraction both
            // see the full text, as before identifiers were used).
            let all = lines.map(\.value).joined(separator: "\n")
            return Fields(title: all, subtitle: "", body: all)
        }
        return Fields(title: title, subtitle: subtitle, body: body)
    }

    private static func joined(_ lines: [Line], tagged identifier: String) -> String {
        lines.filter { $0.identifier?.lowercased() == identifier }
            .map(\.value)
            .joined(separator: "\n")
    }
}
