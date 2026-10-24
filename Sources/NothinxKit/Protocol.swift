import Foundation

/// Wire format of the Nothing / CMF earbuds control channel (RFCOMM, service UUID below).
///
/// Frame: `55 | control(LE16) | command(LE16) | length(LE16) | fsn | payload | crc16(LE, optional)`.
/// CRC is CRC-16/MODBUS over everything before it and is present when `control & 0x20`.
/// Replies carry the request command with bit 15 cleared.
public enum NothingProtocol {
    public static let serviceUUID: [UInt8] = [
        0xae, 0xac, 0x4a, 0x03, 0xdf, 0xf5, 0x49, 0x8f,
        0x84, 0x3a, 0x34, 0x48, 0x7c, 0xf1, 0x33, 0xeb,
    ]

    static let startOfFrame: UInt8 = 0x55
    static let controlDefault: UInt16 = 0x0120
    static let controlBattery: UInt16 = 0x5120

    public enum Command: UInt16, Sendable {
        // Reads
        case firmwareVersion = 0xc042
        case battery = 0xc007
        case audioMode = 0xc01e
        case toggles = 0xc00e
        case equalizer = 0xc050
        case ultraBass = 0xc04e
        case lowLatency = 0xc041
        case gestures = 0xc018
        case spatialAudio = 0xc04f
        // Writes
        case findDevice = 0xf002
        case setGesture = 0xf003
        case setToggle = 0xf004
        case setAudioMode = 0xf00f
        case setEqualizer = 0xf01d
        case setLowLatency = 0xf040
        case setUltraBass = 0xf051
        case setSpatialAudio = 0xf052
        // Unsolicited
        case batteryEvent = 0xe001
        case caseClosedEvent = 0xe002
        case audioModeEvent = 0xe003
    }

    public static func crc16(_ bytes: some Sequence<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xa001 : crc >> 1
            }
        }
        return crc
    }

    public static func encode(_ command: Command, _ payload: [UInt8] = []) -> [UInt8] {
        let control = command == .battery ? controlBattery : controlDefault
        var frame: [UInt8] = [startOfFrame]
        frame += le16(control)
        frame += le16(command.rawValue)
        frame += le16(UInt16(payload.count))
        frame.append(0) // fsn; this family does not use a running counter
        frame += payload
        frame += le16(crc16(frame))
        return frame
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
}

public struct Frame: Equatable, Sendable {
    public let control: UInt16
    /// Command as the request would name it (bit 15 restored).
    public let command: UInt16
    public let payload: [UInt8]

    public var isOK: Bool { control & 0x1f == 0 }
}

/// Splits an RFCOMM byte stream into frames; tolerates frames split across reads or glued together.
public struct FrameDecoder: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while true {
            guard let start = buffer.firstIndex(of: NothingProtocol.startOfFrame) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 8 else { break }
            let control = UInt16(buffer[1]) | UInt16(buffer[2]) << 8
            let command = UInt16(buffer[3]) | UInt16(buffer[4]) << 8
            let length = Int(UInt16(buffer[5]) | UInt16(buffer[6]) << 8)
            let hasCRC = control & 0x20 != 0
            let total = 8 + length + (hasCRC ? 2 : 0)
            guard buffer.count >= total else { break }
            // Replies carry a trailer that is not the request CRC (acks send FF FF), so it is skipped, not checked.
            frames.append(Frame(control: control, command: command | 0x8000, payload: Array(buffer[8..<(8 + length)])))
            buffer.removeFirst(total)
        }
        return frames
    }
}
