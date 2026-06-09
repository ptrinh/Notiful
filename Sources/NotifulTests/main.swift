import Foundation
import NotifulCore

let t = TestKit()

// ───────────────────────── BPlist decoding (real layout from Step 0) ─────────────────────────
// A binary plist matching the REAL structure confirmed on macOS 26:
// top-level "app"; under "req": titl/subt/body. Code value sanitized.
let fixtureBase64 = "YnBsaXN0MDDUAQIDBAUGDxBTYXBwU3JlcVRvcmlnVGRhdGVfEBFjb20uZ29vZ2xlLkNocm9tZdQHCAkKCwwNDlRpZGVuVHN1YnRUdGl0bFRib2R5XxAQcnxEZWZhdWx0fGd2LW90cFBcR29vZ2xlIFZvaWNlXxBGWW91ciBHb29nbGUgVm9pY2UgdmVyaWZpY2F0aW9uIGNvZGUgaXMgMzE4MjA0LiBEbyBub3Qgc2hhcmUgdGhpcyBjb2RlLhAEI0HH65b88euFCBEVGR4jN0BFSk9UZ2h1vsAAAAAAAAABAQAAAAAAAAARAAAAAAAAAAAAAAAAAAAAyQ=="

t.test("decode real layout") {
    let data = Data(base64Encoded: fixtureBase64)!
    let rec = BPlistDecoder.decode(data: data, recID: 8328, bundleID: "com.google.chrome", deliveredDate: 802631161.89)
    t.notNil(rec, "should decode")
    t.equal(rec?.title, "Google Voice", "title")
    t.equal(rec?.subtitle, "", "subtitle")
    t.assert(rec?.body.contains("verification code is 318204") ?? false, "body contains code")
    t.equal(rec?.bundleID, "com.google.chrome", "bundle id from app table")
}

t.test("falls back to plist app when bundle empty") {
    let data = Data(base64Encoded: fixtureBase64)!
    let rec = BPlistDecoder.decode(data: data, recID: 1, bundleID: "", deliveredDate: 0)
    t.equal(rec?.bundleID, "com.google.Chrome", "uses plist app")
}

t.test("rejects empty-text record") {
    let plist: [String: Any] = ["app": "x", "req": ["titl": "", "subt": "", "body": ""]]
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    t.nilCheck(BPlistDecoder.decode(data: data, recID: 1, bundleID: "x", deliveredDate: 0), "empty rejected")
}

t.test("rejects garbage") {
    t.nilCheck(BPlistDecoder.decode(data: Data([0, 1, 2]), recID: 1, bundleID: "x", deliveredDate: 0), "garbage rejected")
}

// ───────────────────────── OTP extraction ─────────────────────────
func ex(_ body: String, title: String = "", regex: String? = nil) -> String? {
    OTPExtractor.extract(title: title, subtitle: "", body: body, regex: regex)
}

t.test("OTP positives") {
    t.equal(ex("Your Google Voice verification code is 318204. Do not share this code."), "318204", "google voice")
    t.equal(ex("G-558943 is your Google verification code"), "558943", "G- format")
    t.equal(ex("Login code: 51924. Do not give this code to anyone."), "51924", "telegram")
    t.equal(ex("Your WhatsApp code: 729-301\nDon't share it."), "729301", "whatsapp split")
    t.equal(ex("Your verification code is 12345678"), "12345678", "8-digit")
    t.equal(ex("", title: "Your code is 9981"), "9981", "code in title")
    t.equal(ex("482915 is your one-time passcode"), "482915", "keyword after digits")
}

t.test("OTP negatives") {
    t.nilCheck(ex("Call me back at 415-555-0199 when you can"), "phone number")
    t.nilCheck(ex("Your payment of $1,250 was received"), "dollar amount")
    t.nilCheck(ex("See you on 12/25/2026 for the event"), "date")
    t.nilCheck(ex("Thanks for your message, talk soon"), "plain chatter")
}

t.test("OTP keyword biasing over phone") {
    t.equal(ex("From 415-555-0199: your code is 663201"), "663201", "prefers code near keyword")
}

t.test("OTP real Google-Voice-delivered bodies (captured from live DB)") {
    t.equal(ex("623940 is your verification code from Payoneer"), "623940", "payoneer")
    t.equal(ex("vbassociation.slack.com Slack login code: 978223"), "978223", "slack login")
    // Amex: code is near "code:", and a 10-digit phone (8005284800) must NOT win.
    t.equal(ex("Amex will never call you for this code: 106781, for online use only. Call 8005284800 now if you did not request it."),
            "106781", "amex code not phone")
    t.equal(ex("044290 is your verification code from Payoneer"), "044290", "leading-zero code")
}

t.test("matcher senderContains checks subtitle (Google Voice puts marker in subtitle)") {
    let gv = Source(name: "Google Voice", match: SourceMatch(senderContains: ["voice.google.com"]))
    let r = NotificationRecord(recID: 1, bundleID: "com.google.chrome",
                               title: "(917) 809-8409", subtitle: "voice.google.com",
                               body: "623940 is your verification code", deliveredDate: 0)
    t.notNil(SourceMatcher.match(record: r, sources: [gv]), "matches via subtitle")
}

t.test("OTP custom regex") {
    t.equal(ex("ACME-AUTH 4452 valid 5m", regex: #"ACME-AUTH (\d{4})"#), "4452", "capture group")
    t.equal(ex("token=ABCD12 end", regex: #"[A-Z]{4}\d{2}"#), "ABCD12", "whole match when no group")
}

// ───────────────────────── Source matching ─────────────────────────
func rec(_ bundle: String, title: String = "", body: String = "") -> NotificationRecord {
    NotificationRecord(recID: 1, bundleID: bundle, title: title, subtitle: "", body: body, deliveredDate: 0)
}

t.test("matcher bundle id (case-insensitive)") {
    let src = Source(name: "Telegram", match: SourceMatch(appBundleIds: ["com.tdesktop.Telegram"]))
    t.notNil(SourceMatcher.match(record: rec("com.tdesktop.telegram"), sources: [src]), "case-insensitive bundle")
}

t.test("matcher senderContains") {
    let src = Source(name: "GV", match: SourceMatch(senderContains: ["Google Voice"]))
    t.notNil(SourceMatcher.match(record: rec("com.google.chrome", title: "Google Voice"), sources: [src]), "sender match")
    t.nilCheck(SourceMatcher.match(record: rec("com.google.chrome", title: "Slack"), sources: [src]), "no sender match")
}

t.test("matcher bodyContains gate") {
    let src = Source(name: "GV", match: SourceMatch(senderContains: ["Google Voice"], bodyContains: ["code"]))
    t.nilCheck(SourceMatcher.match(record: rec("x", title: "Google Voice", body: "hi there"), sources: [src]), "gate blocks")
    t.notNil(SourceMatcher.match(record: rec("x", title: "Google Voice", body: "your code is 1"), sources: [src]), "gate passes")
}

t.test("matcher empty criteria matches nothing") {
    t.nilCheck(SourceMatcher.match(record: rec("anything"), sources: [Source(name: "E", match: SourceMatch())]), "empty")
}

t.test("matcher first source wins") {
    let a = Source(name: "A", match: SourceMatch(appBundleIds: ["com.x"]))
    let b = Source(name: "B", match: SourceMatch(appBundleIds: ["com.x"]))
    t.equal(SourceMatcher.match(record: rec("com.x"), sources: [a, b])?.name, "A", "first wins")
}

// ───────────────────────── Scanner self-exclusion (feedback-loop guard) ─────────────────────────
t.test("scanner ignores its own notifications") {
    // A Notiful-posted notification ("Google Voice · 485204" / "Click to copy") must NOT be detected,
    // or it would re-trigger forever.
    let cfg = Config(sources: [Source(name: "Google Voice",
                                      match: SourceMatch(senderContains: ["Google Voice"]))],
                     clipboardAutoClearSeconds: 0, pollIntervalSeconds: 2)
    final class FakeDB: NotificationDatabase {
        override func fetchRecords(afterRecID: Int64? = nil, afterDate: Double? = nil, limit: Int? = nil) throws -> [NotificationRecord] {
            [NotificationRecord(recID: 99, bundleID: "com.notiful.app",
                                title: "Google Voice · 485204", subtitle: "", body: "Click to copy", deliveredDate: 100)]
        }
    }
    let scanner = NotifulScanner(database: FakeDB(sourceURL: URL(fileURLWithPath: "/dev/null")),
                                 config: cfg, state: nil, launchDate: 0,
                                 excludeBundleIDs: ["com.notiful.app"])
    let hit = try? scanner.scanLatest()
    t.nilCheck(hit ?? nil, "own notification excluded")
}

// ───────────────────────── Config round-trip ─────────────────────────
t.test("config encodes and decodes") {
    let cfg = Config()
    let data = try! JSONEncoder().encode(cfg)
    let back = try! JSONDecoder().decode(Config.self, from: data)
    t.equal(back, cfg, "round trip")
    t.assert(!cfg.sources.isEmpty, "ships with default sources")
}

exit(Int32(t.summary()))
