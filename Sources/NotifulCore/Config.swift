import Foundation

/// Per-source action toggles. All default to the "safe" choice.
public struct SourceActions: Codable, Equatable, Sendable {
    /// Copy the code to the clipboard immediately on arrival (default off — click-to-copy is safer).
    public var autoCopy: Bool
    /// Post Notiful's own actionable notification for this source.
    public var showActionableNotification: Bool
    /// Include an "Open <source>" button. `openTarget` is the URL or bundle id to open.
    public var openButton: Bool
    public var openTarget: String?
    /// Optional shell command run when a code is detected for this source. The notification text and
    /// code are passed as environment variables (NOTIFUL_CODE, NOTIFUL_TITLE, …) — see CommandRunner.
    public var runCommand: String?

    public init(autoCopy: Bool = false,
                showActionableNotification: Bool = true,
                openButton: Bool = false,
                openTarget: String? = nil,
                runCommand: String? = nil) {
        self.autoCopy = autoCopy
        self.showActionableNotification = showActionableNotification
        self.openButton = openButton
        self.openTarget = openTarget
        self.runCommand = runCommand
    }

    // Tolerant decoding: any omitted key falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoCopy = try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? false
        showActionableNotification = try c.decodeIfPresent(Bool.self, forKey: .showActionableNotification) ?? true
        openButton = try c.decodeIfPresent(Bool.self, forKey: .openButton) ?? false
        openTarget = try c.decodeIfPresent(String.self, forKey: .openTarget)
        runCommand = try c.decodeIfPresent(String.self, forKey: .runCommand)
    }
}

/// How to recognise notifications that belong to a source. A notification matches a source
/// when ANY of the supplied criteria match (and `bodyContains`, if set, also matches as a gate).
public struct SourceMatch: Codable, Equatable, Sendable {
    /// Match notifications posted by these app bundle ids (case-insensitive). Use for NATIVE apps.
    public var appBundleIds: [String]?
    /// Substring match (case-insensitive) on the notification sender/title. Use for browser sources.
    public var senderContains: [String]?
    /// Substring match (case-insensitive) on the title.
    public var titleContains: [String]?
    /// Optional extra gate: body must contain one of these substrings (case-insensitive).
    public var bodyContains: [String]?

    public init(appBundleIds: [String]? = nil,
                senderContains: [String]? = nil,
                titleContains: [String]? = nil,
                bodyContains: [String]? = nil) {
        self.appBundleIds = appBundleIds
        self.senderContains = senderContains
        self.titleContains = titleContains
        self.bodyContains = bodyContains
    }
    // All fields optional already; synthesized decoding tolerates omissions.
}

/// A configured source of OTP notifications.
public struct Source: Codable, Equatable, Sendable {
    public var name: String
    public var match: SourceMatch
    /// Optional per-source OTP regex override (else the global default is used).
    public var otpRegex: String?
    public var actions: SourceActions

    public init(name: String,
                match: SourceMatch,
                otpRegex: String? = nil,
                actions: SourceActions = SourceActions()) {
        self.name = name
        self.match = match
        self.otpRegex = otpRegex
        self.actions = actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Source"
        match = try c.decodeIfPresent(SourceMatch.self, forKey: .match) ?? SourceMatch()
        otpRegex = try c.decodeIfPresent(String.self, forKey: .otpRegex)
        actions = try c.decodeIfPresent(SourceActions.self, forKey: .actions) ?? SourceActions()
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var sources: [Source]
    /// Global default OTP regex. Must contain exactly one capture group for the code.
    public var defaultOTPRegex: String
    /// Clear the clipboard this many seconds after copying (0 = never).
    public var clipboardAutoClearSeconds: Int
    /// Watch debounce / fallback poll interval in seconds.
    public var pollIntervalSeconds: Double

    public init(sources: [Source] = Config.defaultSources,
                defaultOTPRegex: String = Config.defaultRegex,
                clipboardAutoClearSeconds: Int = 0,
                pollIntervalSeconds: Double = Config.defaultPollInterval) {
        self.sources = sources
        self.defaultOTPRegex = defaultOTPRegex
        self.clipboardAutoClearSeconds = clipboardAutoClearSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    // Default fallback-poll interval. The real-time path is the kqueue file watcher; this timer is
    // only a safety net (the watcher retries arming on its own after a WAL checkpoint), so a sparse
    // interval keeps idle CPU wakeups minimal.
    public static let defaultPollInterval = 60.0

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decodeIfPresent([Source].self, forKey: .sources) ?? Config.defaultSources
        defaultOTPRegex = try c.decodeIfPresent(String.self, forKey: .defaultOTPRegex) ?? Config.defaultRegex
        clipboardAutoClearSeconds = try c.decodeIfPresent(Int.self, forKey: .clipboardAutoClearSeconds) ?? 0
        pollIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? Config.defaultPollInterval
    }

    // The default regex is intentionally simple; the smart keyword-biased logic lives in OTPExtractor.
    // This pattern matches a standalone 4-8 digit run.
    public static let defaultRegex = #"\b(\d{4,8})\b"#

    /// Ships with sensible examples so the app does something useful out of the box.
    public static var defaultSources: [Source] {
        [
            Source(
                name: "Google Voice",
                match: SourceMatch(
                    senderContains: ["Google Voice", "voice.google.com"],
                    titleContains: ["Google Voice"]
                ),
                actions: SourceActions(openButton: true, openTarget: "https://voice.google.com")
            ),
            Source(
                name: "Telegram",
                match: SourceMatch(appBundleIds: ["com.tdesktop.Telegram", "ru.keepcoder.Telegram"]),
                actions: SourceActions(openButton: true, openTarget: "com.tdesktop.Telegram")
            ),
            Source(
                name: "WhatsApp",
                match: SourceMatch(appBundleIds: ["net.whatsapp.WhatsApp", "WhatsApp"]),
                actions: SourceActions(openButton: true, openTarget: "net.whatsapp.WhatsApp")
            ),
        ]
    }
}

public enum ConfigStore {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Notiful", isDirectory: true)
    }

    public static var configURL: URL { supportDirectory.appendingPathComponent("config.json") }

    /// Load config, creating a default file if none exists. Never throws to the caller — falls back to defaults.
    public static func loadOrCreate() -> Config {
        let url = configURL
        let fm = FileManager.default
        if let data = try? Data(contentsOf: url) {
            do {
                return try JSONDecoder().decode(Config.self, from: data)
            } catch {
                NotifulLog.error("config.json is invalid (\(error.localizedDescription)); using defaults")
                return Config()
            }
        }
        // No file yet — write defaults so the user has something to edit.
        let config = Config()
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: url)
        }
        return config
    }

    /// Persist a config (used by the configuration UI).
    @discardableResult
    public static func save(_ config: Config) -> Bool {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return false }
        do { try data.write(to: configURL); return true } catch { return false }
    }
}
