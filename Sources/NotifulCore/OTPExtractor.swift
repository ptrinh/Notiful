import Foundation

/// Extracts a one-time passcode from notification text.
///
/// Strategy:
///  - If a per-source `regex` is supplied, it wins (capture group 1, else whole match).
///  - Otherwise candidates are 4–8 digit runs (optionally split by one space/hyphen, e.g. "123 456").
///  - A candidate next to an OTP keyword ("code", "verification", "OTP", …) is preferred.
///  - With no keyword nearby, we fall back to the first "clean" candidate that is NOT embedded in a
///    larger number (phone, date, decimal) and not prefixed by a currency symbol.
public enum OTPExtractor {
    /// Keywords that mark a nearby digit run as an OTP. Matched case-insensitively as substrings,
    /// so stems cover their inflections (e.g. "verif" covers verification/verify/vérification).
    static let keywords = [
        // English
        "code", "verification", "verify", "passcode", "one-time", "one time",
        "otp", "2fa", "pin", "security", "confirmation", "access", "auth",
        // Vietnamese
        "mã", "xác minh", "xác nhận", "mật khẩu",
        // Spanish / Portuguese
        "código", "codigo", "verificación", "verificação", "verificacao", "clave", "contraseña",
        // French (code/verification stems shared with English)
        "vérification",
        // German
        "bestätigung", "einmal", "kennwort",
        // Italian
        "codice", "verifica",
        // Indonesian / Malay
        "kode", "verifikasi",
        // Turkish
        "doğrulama", "şifre",
        // Russian / Ukrainian
        "код", "подтвержд", "пароль",
        // Japanese
        "認証", "確認", "コード", "ワンタイム",
        // Chinese (simplified + traditional)
        "验证码", "驗證碼", "验证", "驗證", "动态码",
        // Korean
        "인증", "코드", "비밀번호",
        // Arabic
        "رمز", "تحقق",
        // Hindi
        "कोड", "सत्यापन",
        // Thai
        "รหัส", "ยืนยัน",
    ]

    /// Combine the fields a code might live in. Body first (most common), then title/subtitle.
    static func combinedText(title: String, subtitle: String, body: String) -> String {
        [body, title, subtitle].filter { !$0.isEmpty }.joined(separator: "  •  ")
    }

    public static func extract(title: String, subtitle: String, body: String, regex: String? = nil) -> String? {
        if let custom = regex, !custom.isEmpty {
            return firstMatch(custom, in: combinedText(title: title, subtitle: subtitle, body: body))
        }

        // Extract from the BODY only. The title/subtitle hold the sender, and for SMS short codes
        // (Google Voice, etc.) the sender is itself a 5-6 digit number (e.g. "35127"). When the
        // message isn't an OTP at all, that sender number in the title used to be picked up as a
        // false OTP. Codes always live in the body, so we ignore title/subtitle entirely.
        if let code = keywordCandidate(in: body) { return code }
        if let code = cleanCandidate(in: body) { return code }
        return nil
    }

    /// The candidate closest to an OTP keyword within one field, if any.
    static func keywordCandidate(in text: String) -> String? {
        let lower = text.lowercased() as NSString
        var best: (code: String, dist: Int)?
        for (code, range) in candidates(in: text) {
            if let d = nearestKeywordDistance(lower: lower, range: range) {
                if best == nil || d < best!.dist { best = (code, d) }
            }
        }
        return best?.code
    }

    /// The first candidate that is not part of a larger number / not a currency amount.
    static func cleanCandidate(in text: String) -> String? {
        let ns = text as NSString
        for (code, range) in candidates(in: text) {
            if isEmbeddedInLargerNumber(text: ns, range: range) { continue }
            if hasCurrencyPrefix(text: ns, range: range) { continue }
            return code
        }
        return nil
    }

    public static func extract(record: NotificationRecord, regex: String? = nil) -> String? {
        extract(title: record.title, subtitle: record.subtitle, body: record.body, regex: regex)
    }

    // MARK: - Internals

    static func candidates(in text: String) -> [(code: String, range: NSRange)] {
        // Two groups split by a single space or hyphen, OR a plain run.
        let pattern = #"\d{3,4}[ \-]\d{3,4}|\d{4,8}"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [(String, NSRange)] = []
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            let raw = ns.substring(with: m.range)
            let digits = raw.filter { $0.isNumber }
            if digits.count >= 4 && digits.count <= 8 {
                out.append((digits, m.range))
            }
        }
        return out
    }

    static func nearestKeywordDistance(lower: NSString, range: NSRange, window: Int = 30) -> Int? {
        var minDist: Int?
        for kw in keywords {
            var searchRange = NSRange(location: 0, length: lower.length)
            while searchRange.location < lower.length {
                let r = lower.range(of: kw, range: searchRange)
                if r.location == NSNotFound { break }
                let kwEnd = r.location + r.length
                let candStart = range.location
                let candEnd = range.location + range.length
                let dist: Int
                if candStart >= kwEnd { dist = candStart - kwEnd }
                else if r.location >= candEnd { dist = r.location - candEnd }
                else { dist = 0 }
                if dist <= window, minDist == nil || dist < minDist! { minDist = dist }
                let nextLoc = r.location + max(1, r.length)
                searchRange = NSRange(location: nextLoc, length: max(0, lower.length - nextLoc))
            }
        }
        return minDist
    }

    private static let numberSeparators: Set<Character> = ["-", ".", ",", "/", ":", "+"]
    private static let currencySymbols: Set<Character> = ["$", "€", "£", "¥", "₫", "₩"]

    static func isEmbeddedInLargerNumber(text: NSString, range: NSRange) -> Bool {
        if let before = char(text, range.location - 1), before.isNumber || numberSeparators.contains(before) {
            return true
        }
        let afterIdx = range.location + range.length
        if let after = char(text, afterIdx), after.isNumber || numberSeparators.contains(after) {
            return true
        }
        return false
    }

    static func hasCurrencyPrefix(text: NSString, range: NSRange) -> Bool {
        // Look back past one optional space for a currency symbol.
        var i = range.location - 1
        if let c = char(text, i), c == " " { i -= 1 }
        if let c = char(text, i), currencySymbols.contains(c) { return true }
        return false
    }

    private static func char(_ text: NSString, _ index: Int) -> Character? {
        guard index >= 0, index < text.length else { return nil }
        return Character(UnicodeScalar(text.character(at: index))!)
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
            return ns.substring(with: m.range(at: 1))
        }
        return ns.substring(with: m.range)
    }
}
