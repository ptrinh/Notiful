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

t.test("OTP short-code sender in title must not win (regression)") {
    // Real case: SMS from short code 35127; the sender digits sat in the title right next to the
    // body's trailing "…code" in the old joined-text scoring and beat the real code.
    t.equal(ex("749088 is your Link verification code", title: "35127"), "749088", "body code beats short-code sender")
    t.equal(ex("Your verification code is 482113", title: "28847"), "482113", "another short-code sender")
    // A non-OTP message from a 5-digit short-code sender must yield nothing — the sender's digits
    // live only in the title, and we extract from the body alone.
    t.nilCheck(ex("Are we still on for lunch tomorrow?", title: "35127"), "short-code sender in title is not an OTP")
    t.nilCheck(ex("", title: "Your code is 9981"), "title is never scanned for codes")
}

t.test("OTP multilingual keywords") {
    t.equal(ex("Mã xác minh của bạn là 583920"), "583920", "vietnamese")
    t.equal(ex("Tu código de verificación es 118274"), "118274", "spanish")
    t.equal(ex("您的验证码为 902817，请勿泄露"), "902817", "chinese")
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

// ───────────────────────── OTP extraction (edge cases) ─────────────────────────
t.test("OTP space-split candidate") {
    t.equal(ex("Your code 123 456 expires soon"), "123456", "space-separated pair joined")
}

t.test("OTP rejects non-USD currency amounts (no keyword)") {
    // hasCurrencyPrefix covers $ € £ ¥ ₫ ₩ — only $ was previously exercised.
    t.nilCheck(ex("Balance updated: ₫50000 available"), "dong amount")
    t.nilCheck(ex("Charged £12345 to your card today"), "pound amount")
}

t.test("OTP rejects digits embedded in a longer number") {
    t.nilCheck(ex("Order reference 1234567890123 confirmed"), "13-digit id is not an OTP")
}

t.test("OTP 3-digit run is too short, 4 is the floor") {
    t.nilCheck(ex("Press 123 to continue"), "3 digits rejected")
    t.equal(ex("Your code is 4521"), "4521", "4 digits is the minimum code")
}

t.test("OTP custom regex spans all fields (combinedText)") {
    // The regex path joins body + title + subtitle, so a pattern may match the title.
    t.equal(OTPExtractor.extract(title: "Acme 9921", subtitle: "", body: "Use the code below",
                                 regex: #"Acme (\d{4})"#), "9921", "regex matches text in the title")
}

// ───────────────────────── Source matching (extra criteria) ─────────────────────────
t.test("matcher titleContains") {
    let src = Source(name: "GV", match: SourceMatch(titleContains: ["Google Voice"]))
    t.notNil(SourceMatcher.match(record: rec("com.x", title: "Msg from Google Voice"), sources: [src]), "title substring matches")
    t.nilCheck(SourceMatcher.match(record: rec("com.x", title: "Telegram"), sources: [src]), "no title match")
}

t.test("matcher senderContains is case-insensitive") {
    let src = Source(name: "GV", match: SourceMatch(senderContains: ["google voice"]))
    t.notNil(SourceMatcher.match(record: rec("com.x", title: "GOOGLE VOICE"), sources: [src]), "case-insensitive sender")
}

t.test("matcher bodyContains gate is case-insensitive") {
    let src = Source(name: "GV", match: SourceMatch(titleContains: ["GV"], bodyContains: ["CODE"]))
    t.notNil(SourceMatcher.match(record: rec("x", title: "GV", body: "your code is 12"), sources: [src]),
             "lowercase body satisfies an uppercase needle")
}

// ───────────────────────── NotificationRecord / BPlistDecoder ─────────────────────────
t.test("record sender is the title") {
    t.equal(rec("x", title: "From GV").sender, "From GV", "sender == title")
}

t.test("decoder falls back to top-level fields when there is no req dict") {
    let plist: [String: Any] = ["app": "com.x", "titl": "Hello", "subt": "", "body": "code 4321"]
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    let r = BPlistDecoder.decode(data: data, recID: 2, bundleID: "com.x", deliveredDate: 0)
    t.equal(r?.title, "Hello", "title from top level")
    t.assert(r?.body.contains("4321") ?? false, "body from top level")
}

t.test("decoder accepts a title-only record") {
    let plist: [String: Any] = ["req": ["titl": "Just a title", "subt": "", "body": ""]]
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    t.notNil(BPlistDecoder.decode(data: data, recID: 1, bundleID: "x", deliveredDate: 0), "title-only is actionable")
}

// ───────────────────────── NotifulLog.mask (never leak a full code) ─────────────────────────
t.test("log masks codes for display") {
    t.equal(NotifulLog.mask("318204"), "3••••4", "keeps first/last, dots between")
    t.equal(NotifulLog.mask("4521"), "4••1", "4-digit")
    t.equal(NotifulLog.mask("123"), "1•3", "3-digit")
    t.equal(NotifulLog.mask("12"), "••", "2 chars fully masked")
    t.equal(NotifulLog.mask("7"), "•", "1 char fully masked")
    t.equal(NotifulLog.mask(""), "", "empty stays empty")
}

// ───────────────────────── Config tolerant decoding ─────────────────────────
t.test("config decodes an empty object to safe defaults") {
    let cfg = try! JSONDecoder().decode(Config.self, from: Data("{}".utf8))
    t.assert(!cfg.sources.isEmpty, "missing sources -> default sources")
    t.equal(cfg.defaultOTPRegex, Config.defaultRegex, "missing regex -> default")
    t.equal(cfg.pollIntervalSeconds, Config.defaultPollInterval, "missing interval -> default")
    t.equal(cfg.clipboardAutoClearSeconds, 0, "missing auto-clear -> 0")
}

t.test("source decodes with omitted match/actions to defaults") {
    let src = try! JSONDecoder().decode(Source.self, from: Data(#"{"name":"X"}"#.utf8))
    t.equal(src.name, "X", "name decoded")
    t.equal(src.actions, SourceActions(), "actions fall back to defaults")
}

t.test("SourceActions tolerant decode keeps the safe defaults") {
    let a = try! JSONDecoder().decode(SourceActions.self, from: Data("{}".utf8))
    t.assert(!a.autoCopy, "autoCopy off by default")
    t.assert(a.showActionableNotification, "notifications on by default")
    t.assert(!a.openButton, "open button off by default")
}

// ───────────────────────── StateStore (watermark + write batching) ─────────────────────────
func tempStateURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("notiful-test-state-\(UUID().uuidString).json")
}

t.test("StateStore starts at zero") {
    let s = StateStore(url: tempStateURL())
    t.equal(s.state.lastRecID, 0, "fresh watermark is 0")
    t.assert(!s.isProcessed(recID: 5), "unseen record is not processed")
    t.assert(s.isProcessed(recID: 0), "<= watermark counts as processed")
}

t.test("StateStore advances forward only") {
    let s = StateStore(url: tempStateURL())
    s.advance(recID: 10, deliveredDate: 100)
    t.equal(s.state.lastRecID, 10, "advanced to 10")
    s.advance(recID: 5, deliveredDate: 50)
    t.equal(s.state.lastRecID, 10, "a lower recID never moves the watermark backward")
    t.assert(s.isProcessed(recID: 10), "10 processed")
    t.assert(!s.isProcessed(recID: 11), "11 still new")
}

t.test("StateStore.advance defers the disk write until flush") {
    let url = tempStateURL()
    let s = StateStore(url: url)
    s.advance(recID: 42, deliveredDate: 999)
    t.equal(StateStore(url: url).state.lastRecID, 0, "advance() alone does not persist")
    s.flush()
    let reloaded = StateStore(url: url)
    t.equal(reloaded.state.lastRecID, 42, "flush() persists the watermark")
    t.equal(reloaded.state.lastDeliveredDate, 999, "delivered date persisted too")
}

t.test("StateStore.markProcessed persists immediately") {
    let url = tempStateURL()
    StateStore(url: url).markProcessed(recID: 7, deliveredDate: 70)
    t.equal(StateStore(url: url).state.lastRecID, 7, "markProcessed flushes on the spot")
}

// ───────────────────────── Scanner.scanNew (incremental scan) ─────────────────────────
// A stub DB that mimics the real SQL: newest-first, honouring the afterRecID/afterDate filters.
final class StubDB: NotificationDatabase {
    let records: [NotificationRecord]
    init(_ records: [NotificationRecord]) {
        self.records = records
        super.init(sourceURL: URL(fileURLWithPath: "/dev/null"))
    }
    override func fetchRecords(afterRecID: Int64? = nil, afterDate: Double? = nil, limit: Int? = nil) throws -> [NotificationRecord] {
        records
            .filter { afterRecID == nil || $0.recID > afterRecID! }
            .filter { afterDate == nil || $0.deliveredDate > afterDate! }
            .sorted { ($0.deliveredDate, $0.recID) > ($1.deliveredDate, $1.recID) }
    }
}

let gvSource = Source(name: "Google Voice", match: SourceMatch(senderContains: ["Google Voice"]))
func gvRecord(_ recID: Int64, code: String, date: Double) -> NotificationRecord {
    NotificationRecord(recID: recID, bundleID: "com.google.chrome", title: "Google Voice",
                       subtitle: "", body: "Your code is \(code)", deliveredDate: date)
}

t.test("scanNew returns matches oldest-first and advances the watermark") {
    let db = StubDB([gvRecord(1, code: "111111", date: 10),
                     gvRecord(2, code: "222222", date: 20),
                     gvRecord(3, code: "333333", date: 30)])
    let state = StateStore(url: tempStateURL())
    let scanner = NotifulScanner(database: db, config: Config(sources: [gvSource]), state: state, launchDate: 0)
    let hits = (try? scanner.scanNew()) ?? []
    t.equal(hits.map { $0.code }, ["111111", "222222", "333333"], "processed oldest-first")
    t.equal(state.state.lastRecID, 3, "watermark advanced to the newest record")
}

t.test("scanNew de-dupes records seen on a previous scan") {
    let db = StubDB([gvRecord(1, code: "111111", date: 10), gvRecord(2, code: "222222", date: 20)])
    let state = StateStore(url: tempStateURL())
    let scanner = NotifulScanner(database: db, config: Config(sources: [gvSource]), state: state, launchDate: 0)
    _ = try? scanner.scanNew()
    t.assert(((try? scanner.scanNew()) ?? []).isEmpty, "a second scan finds nothing new")
}

t.test("scanNew ignores notifications older than launchDate") {
    let db = StubDB([gvRecord(1, code: "111111", date: 5),    // before launch
                     gvRecord(2, code: "222222", date: 50)])  // after launch
    let scanner = NotifulScanner(database: db, config: Config(sources: [gvSource]),
                                 state: StateStore(url: tempStateURL()), launchDate: 10)
    t.equal(((try? scanner.scanNew()) ?? []).map { $0.code }, ["222222"], "stale pre-launch code skipped")
}

t.test("scanNew advances the watermark past unmatched records too (no re-scan)") {
    let other = NotificationRecord(recID: 5, bundleID: "com.other", title: "Slack", subtitle: "",
                                   body: "hello 123456", deliveredDate: 25)
    let db = StubDB([gvRecord(1, code: "111111", date: 10), other])
    let state = StateStore(url: tempStateURL())
    let scanner = NotifulScanner(database: db, config: Config(sources: [gvSource]), state: state, launchDate: 0)
    let hits = (try? scanner.scanNew()) ?? []
    t.equal(hits.map { $0.code }, ["111111"], "only the Google Voice record matched")
    t.equal(state.state.lastRecID, 5, "watermark still moved past the unmatched record")
}

t.test("scanNew handles a burst larger than the old 30-row cap") {
    // 1.1.0 removed the fixed row cap so a burst can never advance the watermark past unseen rows.
    let burst = (1...40).map { gvRecord(Int64($0), code: String(format: "%06d", $0), date: Double($0)) }
    let scanner = NotifulScanner(database: StubDB(burst), config: Config(sources: [gvSource]),
                                 state: StateStore(url: tempStateURL()), launchDate: 0)
    t.equal((try? scanner.scanNew())?.count, 40, "all 40 codes in the burst are captured")
}

exit(Int32(t.summary()))
