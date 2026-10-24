import Foundation

public enum NoiseMode: UInt8, CaseIterable, Sendable, Codable {
    case ancHigh = 0x01
    case ancMid = 0x02
    case ancLow = 0x03
    case ancAdaptive = 0x04
    case off = 0x05
    case transparency = 0x07

    public var isANC: Bool { [.ancHigh, .ancMid, .ancLow, .ancAdaptive].contains(self) }

    public var title: String {
        switch self {
        case .ancHigh: String(localized: "High", bundle: #bundle)
        case .ancMid: String(localized: "Medium", bundle: #bundle)
        case .ancLow: String(localized: "Low", bundle: #bundle)
        case .ancAdaptive: String(localized: "Adaptive", bundle: #bundle)
        case .off: String(localized: "Off", bundle: #bundle)
        case .transparency: String(localized: "Transparency", bundle: #bundle)
        }
    }

    public static let ancLevels: [NoiseMode] = [.ancAdaptive, .ancHigh, .ancMid, .ancLow]
}

public enum EQPreset: UInt8, CaseIterable, Sendable {
    case balanced = 0x00
    case rock = 0x01
    case electronic = 0x02
    case pop = 0x03
    case vocals = 0x04
    case classical = 0x05
    case custom = 0x06
    case dirac = 0x07

    public var title: String {
        switch self {
        case .balanced: String(localized: "Balanced", bundle: #bundle)
        case .rock: String(localized: "Rock", bundle: #bundle)
        case .electronic: String(localized: "Electronic", bundle: #bundle)
        case .pop: String(localized: "Pop", bundle: #bundle)
        case .vocals: String(localized: "Enhance vocals", bundle: #bundle)
        case .classical: String(localized: "Classical", bundle: #bundle)
        case .custom: String(localized: "Custom (from Nothing X)", bundle: #bundle)
        case .dirac: "Dirac Opteo"
        }
    }
}

public enum Earbud: UInt8, Sendable, CaseIterable {
    case left = 0x02
    case right = 0x03

    public var title: String { self == .left ? String(localized: "Left", bundle: #bundle) : String(localized: "Right", bundle: #bundle) }
}

public enum Gesture: UInt8, CaseIterable, Sendable {
    case doubleTap = 0x02
    case tripleTap = 0x03
    case hold = 0x07
    case doubleTapHold = 0x09

    public var title: String {
        switch self {
        case .doubleTap: String(localized: "Double tap", bundle: #bundle)
        case .tripleTap: String(localized: "Triple tap", bundle: #bundle)
        case .hold: String(localized: "Tap and hold", bundle: #bundle)
        case .doubleTapHold: String(localized: "Double tap and hold", bundle: #bundle)
        }
    }
}

public enum GestureAction: UInt8, CaseIterable, Sendable {
    case none = 0x01
    case playPause = 0x02
    case previous = 0x08
    case next = 0x09
    case voiceAssistant = 0x0b
    case volumeUp = 0x12
    case volumeDown = 0x13
    case noiseAll = 0x0a
    case noiseANCTransparency = 0x16
    case noiseANCOff = 0x14
    case noiseTransparencyOff = 0x15

    public var title: String {
        switch self {
        case .none: String(localized: "Nothing", bundle: #bundle)
        case .playPause: String(localized: "Play / pause", bundle: #bundle)
        case .previous: String(localized: "Previous track", bundle: #bundle)
        case .next: String(localized: "Next track", bundle: #bundle)
        case .voiceAssistant: String(localized: "Voice assistant", bundle: #bundle)
        case .volumeUp: String(localized: "Volume up", bundle: #bundle)
        case .volumeDown: String(localized: "Volume down", bundle: #bundle)
        case .noiseAll: String(localized: "ANC ⇄ Transparency ⇄ Off", bundle: #bundle)
        case .noiseANCTransparency: String(localized: "ANC ⇄ Transparency", bundle: #bundle)
        case .noiseANCOff: String(localized: "ANC ⇄ Off", bundle: #bundle)
        case .noiseTransparencyOff: String(localized: "Transparency ⇄ Off", bundle: #bundle)
        }
    }
}

public struct GestureKey: Hashable, Sendable {
    public let bud: Earbud
    public let gesture: Gesture

    public init(bud: Earbud, gesture: Gesture) {
        self.bud = bud
        self.gesture = gesture
    }
}

public struct Battery: Equatable, Sendable, Codable {
    public var level: Int
    public var charging: Bool

    public init(level: Int, charging: Bool) {
        self.level = level
        self.charging = charging
    }
}

/// Everything known about the earbuds; updated from decoded frames.
public struct BudsState: Equatable, Sendable {
    public var firmware: String?
    public var left: Battery?
    public var right: Battery?
    public var caseBattery: Battery?
    public var noiseMode: NoiseMode?
    /// ANC level the buds return to when switching back to noise cancelling.
    public var lastANCLevel: NoiseMode?
    public var inEarDetection: Bool?
    public var equalizer: EQPreset?
    public var ultraBassEnabled: Bool?
    public var ultraBassLevel: Int?
    public var lowLatency: Bool?
    public var spatialAudio: Bool?
    public var gestures: [GestureKey: GestureAction] = [:]
    /// Whether each bud sits in an ear, from the wear event; nil until the buds report it.
    public var inEar: [Earbud: Bool] = [:]

    public init() {}

    static let toggleInEar: UInt8 = 0x01

    /// Applies a frame and returns whether it changed anything.
    @discardableResult
    public mutating func apply(_ frame: Frame) -> Bool {
        guard frame.isOK, let command = NothingProtocol.Command(rawValue: frame.command) else { return false }
        let before = self
        let p = frame.payload
        switch command {
        case .firmwareVersion:
            firmware = String(decoding: p, as: UTF8.self)
        case .battery, .batteryEvent:
            applyBattery(p)
        case .audioMode:
            // Triples of (id, value, 0): id 1 = current mode, id 2 = remembered ANC level.
            var i = 0
            while i + 1 < p.count {
                if p[i] == 0x01 { noiseMode = NoiseMode(rawValue: p[i + 1]) }
                if p[i] == 0x02 { lastANCLevel = NoiseMode(rawValue: p[i + 1]) }
                i += 3
            }
        case .audioModeEvent:
            if p.count >= 2, p[0] == 0x01, let mode = NoiseMode(rawValue: p[1]) {
                noiseMode = mode
                if mode.isANC { lastANCLevel = mode }
            }
        case .toggles:
            // count, then (id, enabled) pairs.
            guard let count = p.first else { break }
            for n in 0..<Int(count) where 2 + 2 * n < p.count {
                if p[1 + 2 * n] == Self.toggleInEar { inEarDetection = p[2 + 2 * n] == 0x01 }
            }
        case .equalizer:
            if let code = p.first { equalizer = EQPreset(rawValue: code) }
        case .wearEvent:
            // count, then (device, state); low nibble 0xC = in ear, 0xA = out, 0x8 = in the case.
            guard let count = p.first else { break }
            for n in 0..<Int(count) where 2 + 2 * n < p.count {
                guard let bud = Earbud(rawValue: p[1 + 2 * n]) else { continue }
                inEar[bud] = p[2 + 2 * n] & 0x0f == 0x0c
            }
        case .ultraBass:
            if p.count >= 1 { ultraBassEnabled = p[0] == 0x01 }
            if p.count >= 2 { ultraBassLevel = max(1, min(5, (Int(p[1]) + 1) / 2)) }
        case .lowLatency:
            if let v = p.first { lowLatency = v == 0x01 }
        case .spatialAudio:
            if let v = p.first { spatialAudio = v == 0x01 }
        case .gestures:
            // count, then (device, context, gesture, action); device 4 is the case dial.
            guard let count = p.first else { break }
            for n in 0..<Int(count) {
                let o = 1 + 4 * n
                guard o + 3 < p.count,
                      let bud = Earbud(rawValue: p[o]),
                      let gesture = Gesture(rawValue: p[o + 2]),
                      let action = GestureAction(rawValue: p[o + 3]) else { continue }
                gestures[GestureKey(bud: bud, gesture: gesture)] = action
            }
        default:
            break
        }
        return self != before
    }

    private mutating func applyBattery(_ p: [UInt8]) {
        guard let count = p.first else { return }
        var seenCase = false
        for n in 0..<Int(count) where 2 + 2 * n < p.count {
            let raw = p[2 + 2 * n]
            let battery = Battery(level: Int(raw & 0x7f), charging: raw & 0x80 != 0)
            switch p[1 + 2 * n] {
            case 0x02: left = battery
            case 0x03: right = battery
            case 0x04: caseBattery = battery; seenCase = true
            default: break
            }
        }
        // The case only reports while a bud sits in it.
        if !seenCase { caseBattery = nil }
    }
}

public extension NothingProtocol {
    static let initialQueries: [Command] = [
        .firmwareVersion, .battery, .audioMode, .toggles, .equalizer,
        .ultraBass, .lowLatency, .gestures, .spatialAudio,
    ]

    static func setNoiseMode(_ mode: NoiseMode) -> [UInt8] { encode(.setAudioMode, [0x01, mode.rawValue, 0x00]) }
    static func setInEarDetection(_ on: Bool) -> [UInt8] { encode(.setToggle, [0x01, BudsState.toggleInEar, on ? 1 : 0]) }
    static func setEqualizer(_ preset: EQPreset) -> [UInt8] { encode(.setEqualizer, [preset.rawValue, 0x00]) }
    static func setUltraBass(_ on: Bool, level: Int) -> [UInt8] {
        encode(.setUltraBass, [on ? 1 : 0, UInt8(max(1, min(5, level)) * 2)])
    }
    static func setLowLatency(_ on: Bool) -> [UInt8] { encode(.setLowLatency, [on ? 0x01 : 0x02]) }
    static func setSpatialAudio(_ on: Bool) -> [UInt8] { encode(.setSpatialAudio, [on ? 1 : 0]) }
    static func setGesture(_ key: GestureKey, _ action: GestureAction) -> [UInt8] {
        encode(.setGesture, [0x01, key.bud.rawValue, 0x01, key.gesture.rawValue, action.rawValue])
    }
    /// CMF buds ring one side at a time; the single-byte form used by Ear (1) is ignored.
    static func findDevice(_ bud: Earbud, ringing: Bool) -> [UInt8] {
        encode(.findDevice, [bud.rawValue, ringing ? 1 : 0])
    }
}
