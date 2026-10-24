import Foundation

/// What the app hands to the widget and controls through the shared App Group.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var name: String
    public var connected: Bool
    public var left: Battery?
    public var right: Battery?
    public var caseBattery: Battery?
    public var noiseMode: NoiseMode?
    public var updated: Date

    public init(
        name: String,
        connected: Bool,
        left: Battery?,
        right: Battery?,
        caseBattery: Battery?,
        noiseMode: NoiseMode?,
        updated: Date = .now
    ) {
        self.name = name
        self.connected = connected
        self.left = left
        self.right = right
        self.caseBattery = caseBattery
        self.noiseMode = noiseMode
        self.updated = updated
    }

    public static let appGroup = "2C76W4D5L5.dev.nothinx"
    static let key = "widgetSnapshot"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.key)
    }
}

/// Noise-mode choice as the widget and controls offer it; ANC means "at the last used level".
public enum NoiseChoice: String, Codable, Sendable, CaseIterable {
    case anc, transparency, off

    public init(_ mode: NoiseMode) {
        self = mode.isANC ? .anc : mode == .transparency ? .transparency : .off
    }
}

/// Widget and control extensions cannot reach Bluetooth, so they leave a request in the App Group
/// and ring a Darwin notification; the running app picks it up and talks to the buds.
public enum WidgetCommand {
    public static let notification = "dev.nothinx.command"
    static let key = "pendingNoiseChoice"

    public static func send(_ choice: NoiseChoice) {
        WidgetSnapshot.defaults?.set(choice.rawValue, forKey: key)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notification as CFString),
            nil, nil, true
        )
    }

    /// Returns and clears the pending request.
    public static func take() -> NoiseChoice? {
        guard let raw = WidgetSnapshot.defaults?.string(forKey: key) else { return nil }
        WidgetSnapshot.defaults?.removeObject(forKey: key)
        return NoiseChoice(rawValue: raw)
    }
}
