import Foundation
import NothinxKit
import Observation
import ServiceManagement
import WidgetKit

enum MenuBarDisplay: String, CaseIterable {
    case icon, battery, mode

    var title: String {
        switch self {
        case .icon: "Только иконка"
        case .battery: "Заряд"
        case .mode: "Режим шумодава"
        }
    }
}

/// App-facing model: current state plus the actions the panel can trigger.
@MainActor
@Observable
final class BudsController {
    private(set) var status: BudsConnection.Status = .noDevice
    private(set) var state = BudsState()
    private(set) var deviceName = "CMF Buds"
    private(set) var ringing: Set<Earbud> = []
    private(set) var lastSeenBattery: [Battery?] = [nil, nil]

    var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay") }
    }

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                try launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private let connection = BudsConnection()
    private var pollTask: Task<Void, Never>?

    init() {
        menuBarDisplay = MenuBarDisplay(rawValue: UserDefaults.standard.string(forKey: "menuBarDisplay") ?? "") ?? .battery
        lastSeenBattery = [Self.loadBattery("left"), Self.loadBattery("right")]
        connection.onStatus = { [weak self] in self?.statusChanged($0) }
        connection.onFrame = { [weak self] in self?.received($0) }
        connection.start()
        if Self.hasWidget { listenForWidgetCommands() }
    }

    /// The public release ships without the widget (it needs a team-signed App Group),
    /// and touching the App Group unsigned would make macOS ask about other apps' data.
    private static let hasWidget = Bundle.main.builtInPlugInsURL.map {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("NothinxWidget.appex").path)
    } ?? false

    /// Picks up noise-mode taps from the widget and Control Center (see WidgetCommand).
    private func listenForWidgetCommands() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .widgetCommand, object: nil)
                }
            },
            WidgetCommand.notification as CFString,
            nil,
            .deliverImmediately
        )
        NotificationCenter.default.addObserver(forName: .widgetCommand, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWidgetCommand() }
        }
    }

    private func handleWidgetCommand() {
        guard let choice = WidgetCommand.take(), isConnected else {
            publishWidget()
            return
        }
        switch choice {
        case .anc: enableANC()
        case .transparency: setNoiseMode(.transparency)
        case .off: setNoiseMode(.off)
        }
        publishWidget()
    }

    var isConnected: Bool { status == .connected }

    /// Lowest earbud charge, live when connected, otherwise last seen.
    var lowestBudBattery: Int? {
        let buds = isConnected ? [state.left, state.right] : lastSeenBattery
        return buds.compactMap { $0?.level }.min()
    }

    // MARK: Actions

    func connect() { connection.connect() }
    func reconnect() { connection.reconnect() }

    /// The buds confirm a mode change with an audio-mode event, but a status read sent right
    /// after the write can still return the old mode and make the panel flicker back.
    /// So while a change is pending, stale reads are ignored and the event is the confirmation.
    private var pendingNoiseMode: NoiseMode?
    private var noiseFallback: Task<Void, Never>?

    func setNoiseMode(_ mode: NoiseMode) {
        state.noiseMode = mode
        if mode.isANC { state.lastANCLevel = mode }
        pendingNoiseMode = mode
        connection.send(NothingProtocol.setNoiseMode(mode))
        noiseFallback?.cancel()
        noiseFallback = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !Task.isCancelled else { return }
            self.pendingNoiseMode = nil
            self.connection.send(NothingProtocol.encode(.audioMode))
        }
    }

    /// Switches to noise cancelling at the level the buds last used.
    func enableANC() { setNoiseMode(state.lastANCLevel ?? .ancHigh) }

    func setEqualizer(_ preset: EQPreset) {
        state.equalizer = preset
        sendAndRefresh(NothingProtocol.setEqualizer(preset), .equalizer)
    }

    func setUltraBass(enabled: Bool) {
        state.ultraBassEnabled = enabled
        sendAndRefresh(NothingProtocol.setUltraBass(enabled, level: state.ultraBassLevel ?? 3), .ultraBass)
    }

    func setUltraBass(level: Int) {
        state.ultraBassLevel = level
        sendAndRefresh(NothingProtocol.setUltraBass(state.ultraBassEnabled ?? true, level: level), .ultraBass)
    }

    func setInEarDetection(_ on: Bool) {
        state.inEarDetection = on
        sendAndRefresh(NothingProtocol.setInEarDetection(on), .toggles)
    }

    func setLowLatency(_ on: Bool) {
        state.lowLatency = on
        sendAndRefresh(NothingProtocol.setLowLatency(on), .lowLatency)
    }

    func setSpatialAudio(_ on: Bool) {
        state.spatialAudio = on
        sendAndRefresh(NothingProtocol.setSpatialAudio(on), .spatialAudio)
    }

    func setGesture(_ key: GestureKey, _ action: GestureAction) {
        state.gestures[key] = action
        sendAndRefresh(NothingProtocol.setGesture(key, action), .gestures)
    }

    func toggleRinging(_ bud: Earbud) {
        let ring = !ringing.contains(bud)
        if ring { ringing.insert(bud) } else { ringing.remove(bud) }
        connection.send(NothingProtocol.findDevice(bud, ringing: ring))
    }

    // MARK: Plumbing

    /// Writes optimistically, then re-reads so the panel shows what the buds actually accepted.
    private func sendAndRefresh(_ command: [UInt8], _ query: NothingProtocol.Command) {
        connection.send(command)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            connection.send(NothingProtocol.encode(query))
        }
    }

    private func statusChanged(_ newStatus: BudsConnection.Status) {
        status = newStatus
        defer { publishWidget() }
        if let name = connection.deviceName { deviceName = name }
        pollTask?.cancel()
        guard newStatus == .connected else {
            ringing = []
            return
        }
        state = BudsState()
        for query in NothingProtocol.initialQueries {
            connection.send(NothingProtocol.encode(query))
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.connection.send(NothingProtocol.encode(.battery))
            }
        }
    }

    private func received(_ frame: Frame) {
        if let pending = pendingNoiseMode {
            switch NothingProtocol.Command(rawValue: frame.command) {
            case .audioModeEvent:
                if frame.payload.count >= 2, frame.payload[1] == pending.rawValue {
                    pendingNoiseMode = nil
                    noiseFallback?.cancel()
                } else {
                    return // an earlier click's confirmation; the latest one is still on its way
                }
            case .audioMode:
                return
            default:
                break
            }
        }
        let wasInEar = state.inEar
        guard state.apply(frame) else { return }
        publishWidget()
        if frame.command == NothingProtocol.Command.wearEvent.rawValue {
            wearChanged(from: wasInEar)
        }
        if frame.command == NothingProtocol.Command.toggles.rawValue, state.inEarDetection == true {
            // Ask for the media-key permission up front, not on the first removal.
            MediaControl.ensureAccess()
        }
        if frame.command == NothingProtocol.Command.battery.rawValue
            || frame.command == NothingProtocol.Command.batteryEvent.rawValue {
            lastSeenBattery = [state.left, state.right]
            Self.saveBattery(state.left, "left")
            Self.saveBattery(state.right, "right")
        }
    }

    /// Set when taking a bud out paused playback, so putting it back resumes only what we paused.
    private var pausedByWear = false

    private func wearChanged(from old: [Earbud: Bool]) {
        guard state.inEarDetection == true else { return }
        let bothBefore = old[.left] == true && old[.right] == true
        let bothNow = state.inEar[.left] == true && state.inEar[.right] == true
        if bothBefore, !bothNow, MediaControl.isPlaying {
            MediaControl.pressPlayPause()
            pausedByWear = true
        } else if bothNow, pausedByWear {
            pausedByWear = false
            // Some players keep the output device running while paused, so it is not checked here.
            MediaControl.pressPlayPause()
        }
    }

    /// Hands battery levels to the widget; it keeps the last levels while disconnected.
    private func publishWidget() {
        guard Self.hasWidget else { return }
        let previous = WidgetSnapshot.load()
        let snapshot = WidgetSnapshot(
            name: deviceName,
            connected: isConnected,
            left: state.left ?? lastSeenBattery[0],
            right: state.right ?? lastSeenBattery[1],
            caseBattery: isConnected ? state.caseBattery : nil,
            noiseMode: isConnected ? state.noiseMode : nil
        )
        var comparable = snapshot
        comparable.updated = previous?.updated ?? snapshot.updated
        guard comparable != previous else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    private static func loadBattery(_ key: String) -> Battery? {
        guard let data = UserDefaults.standard.data(forKey: "battery.\(key)") else { return nil }
        return try? JSONDecoder().decode(Battery.self, from: data)
    }

    private static func saveBattery(_ battery: Battery?, _ key: String) {
        guard let battery, let data = try? JSONEncoder().encode(battery) else { return }
        UserDefaults.standard.set(data, forKey: "battery.\(key)")
    }
}

private extension Notification.Name {
    static let widgetCommand = Notification.Name("dev.nothinx.widgetCommand")
}
