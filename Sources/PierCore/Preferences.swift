import Foundation

public extension Notification.Name {
    static let pierPreferencesChanged = Notification.Name("app.openware.pier.preferences")
}

/// App-wide settings. Anything that belongs to a single dock lives on the dock itself.
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.launchAtLogin: false,
            Key.showMenuBarIcon: true,
            Key.animateLaunches: true,
            Key.confirmedFirstRun: false,
        ])
    }

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let animateLaunches = "animateLaunches"
        static let confirmedFirstRun = "confirmedFirstRun"
    }

    public var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Key.showMenuBarIcon) }
        set { write(newValue, Key.showMenuBarIcon) }
    }

    /// The bounce when you click an app that isn't running yet.
    public var animateLaunches: Bool {
        get { defaults.bool(forKey: Key.animateLaunches) }
        set { write(newValue, Key.animateLaunches) }
    }

    public var confirmedFirstRun: Bool {
        get { defaults.bool(forKey: Key.confirmedFirstRun) }
        set { defaults.set(newValue, forKey: Key.confirmedFirstRun) }
    }

    private func write(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .pierPreferencesChanged, object: self)
    }
}
