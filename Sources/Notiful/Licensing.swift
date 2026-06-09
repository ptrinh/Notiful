import Foundation
import NotifulCore

/// App-side licensing: a 60-day trial, then a soft nag. Perpetual one-time licenses are verified
/// OFFLINE against an embedded public key (see NotifulCore/License). Nothing is gated — capture keeps
/// working after the trial — we just remind the user to buy a license.
enum Licensing {
    private static let defaults = UserDefaults.standard

    /// Public key for verifying licenses (matches the private key held by the vendor). It's safe to
    /// ship publicly — it can only VERIFY licenses, never sign them.
    static let publicKeyHex = "a37013af217f318f41bbb235acda31fe11ac8fdd895cbb7248c0f5eb5788b49b"

    /// Where buyers go to purchase. Set this to your Paddle / Lemon Squeezy / Gumroad checkout URL.
    static let purchaseURL = URL(string: "https://github.com/ptrinh/Notiful#buy")!

    static let trialDays = 60

    private enum Key {
        static let licenseString = "licenseString"
        static let firstLaunch = "firstLaunchDate"
    }

    // MARK: - Status

    enum Status: Equatable {
        case licensed(email: String)
        case trial(daysLeft: Int)
        case trialExpired
    }

    /// Record the first-launch timestamp once, so the trial clock starts on first run.
    static func startTrialClockIfNeeded() {
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(Date().timeIntervalSinceReferenceDate, forKey: Key.firstLaunch)
        }
    }

    static var current: Status {
        if let email = licensedEmail { return .licensed(email: email) }
        let left = trialDaysLeft
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }

    static var isLicensed: Bool { licensedEmail != nil }

    /// The verified email if a valid license is stored, else nil.
    static var licensedEmail: String? {
        guard let stored = defaults.string(forKey: Key.licenseString) else { return nil }
        return (try? LicenseCodec.verify(stored, publicKeyHex: publicKeyHex))?.email
    }

    private static var trialDaysLeft: Int {
        guard let start = defaults.object(forKey: Key.firstLaunch) as? Double else { return trialDays }
        let elapsed = Date().timeIntervalSinceReferenceDate - start
        let used = Int(elapsed / 86_400)
        return max(0, trialDays - used)
    }

    // MARK: - Activation

    /// Validate and store a license string. Returns the verified email on success, or throws.
    @discardableResult
    static func activate(_ licenseString: String) throws -> String {
        let license = try LicenseCodec.verify(licenseString, publicKeyHex: publicKeyHex)
        defaults.set(licenseString.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.licenseString)
        return license.email
    }

    static func deactivate() {
        defaults.removeObject(forKey: Key.licenseString)
    }

    /// Short label for the menu's status header.
    static var menuStatusLine: String {
        switch current {
        case .licensed(let email): return "Licensed to \(email)"
        case .trial(let days): return "Trial — \(days) day\(days == 1 ? "" : "s") left"
        case .trialExpired: return "⚠️ Trial ended — buy a license"
        }
    }
}
