import Foundation

/// App-managed UI preferences (kept in UserDefaults, separate from the user-editable config.json).
enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let welcomeShown = "welcomeShown"
        static let hideMenuBarIcon = "hideMenuBarIcon"
        static let notificationsEnabled = "notificationsEnabled"
        static let instantCapture = "instantCapture"
        static let autoDismissSourceBanner = "autoDismissSourceBanner"
    }

    /// Read on-screen banners via Accessibility for instant capture (vs the ~5s database delay).
    static var instantCapture: Bool {
        get { defaults.bool(forKey: Key.instantCapture) }
        set { defaults.set(newValue, forKey: Key.instantCapture) }
    }

    /// After instant-capturing a code, dismiss the source app's banner so only Notiful's remains.
    static var autoDismissSourceBanner: Bool {
        get { defaults.bool(forKey: Key.autoDismissSourceBanner) }
        set { defaults.set(newValue, forKey: Key.autoDismissSourceBanner) }
    }

    /// Whether Notiful posts its own actionable notifications. Defaults to true (on).
    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notificationsEnabled) == nil ? true : defaults.bool(forKey: Key.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    static var welcomeShown: Bool {
        get { defaults.bool(forKey: Key.welcomeShown) }
        set { defaults.set(newValue, forKey: Key.welcomeShown) }
    }

    static var hideMenuBarIcon: Bool {
        get { defaults.bool(forKey: Key.hideMenuBarIcon) }
        set { defaults.set(newValue, forKey: Key.hideMenuBarIcon) }
    }
}
