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
            Key.onlyWithMultipleDisplays: true,
        ])
    }

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let animateLaunches = "animateLaunches"
        static let confirmedFirstRun = "confirmedFirstRun"
        static let onlyWithMultipleDisplays = "onlyWithMultipleDisplays"
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

    /// On by default: on a single display Pier has nothing to add over the system Dock, so
    /// it stands down and comes back when a second display is connected. Off means every
    /// dock shows whenever its own display is present, however many there are.
    public var onlyWithMultipleDisplays: Bool {
        get { defaults.bool(forKey: Key.onlyWithMultipleDisplays) }
        set { write(newValue, Key.onlyWithMultipleDisplays) }
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
