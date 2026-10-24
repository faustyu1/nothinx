import Testing
@testable import NothinxKit

/// Byte sequences captured from a CMF Buds Pro 2 (firmware 1.0.1.74).
private func bytes(_ hex: String) -> [UInt8] {
    hex.split(separator: " ").map { UInt8($0, radix: 16)! }
}

@Test func encodesRequestsLikeTheOfficialApp() {
    #expect(NothingProtocol.encode(.firmwareVersion) == bytes("55 20 01 42 C0 00 00 00 E1 14"))
    #expect(NothingProtocol.encode(.battery) == bytes("55 20 51 07 C0 00 00 00 20 8B"))
    #expect(NothingProtocol.setNoiseMode(.ancHigh) == bytes("55 20 01 0F F0 03 00 00 01 01 00 FA FF"))
    #expect(NothingProtocol.setNoiseMode(.transparency) == bytes("55 20 01 0F F0 03 00 00 01 07 00 F9 5F"))
    #expect(NothingProtocol.findDevice(.left, ringing: true) == bytes("55 20 01 02 F0 02 00 00 02 01 B5 0B"))
    #expect(NothingProtocol.findDevice(.right, ringing: false) == bytes("55 20 01 02 F0 02 00 00 03 00 75 5B"))
}

@Test func decodesGluedAndSplitFrames() {
    var decoder = FrameDecoder()
    let ack = bytes("55 20 01 0F 70 00 00 00 FF FF")
    let event = bytes("55 00 01 03 E0 03 00 00 01 03 00")
    let stream = ack + event
    #expect(decoder.feed(Array(stream[0..<5])).isEmpty)
    let frames = decoder.feed(Array(stream[5...]))
    #expect(frames.map(\.command) == [0xf00f, 0xe003])
    #expect(frames[1].payload == [0x01, 0x03, 0x00])
}

@Test func skipsGarbageBeforeStartOfFrame() {
    var decoder = FrameDecoder()
    let frames = decoder.feed(bytes("00 13 55 20 01 50 40 01 00 00 00 BF 40"))
    #expect(frames == [Frame(control: 0x0120, command: 0xc050, payload: [0x00])])
}

@Test func appliesCapturedStatus() {
    var decoder = FrameDecoder()
    var state = BudsState()
    let captured = [
        "55 20 01 42 40 08 00 00 31 2E 30 2E 31 2E 37 34 D8 35",
        "55 20 51 07 40 05 00 00 02 02 64 03 64 1C BC",
        "55 20 01 1E 40 06 00 00 02 04 00 01 07 00 A3 C9",
        "55 20 01 0E 40 1D 00 00 0E 01 01 02 00 03 01 07 01 09 01 0A 00 0B 00 0C 01 0E 01 0F 01 12 01 15 01 16 01 18 01 00 8A",
        "55 20 01 50 40 01 00 00 00 BF 40",
        "55 20 01 4E 40 02 00 00 01 0A 80 27",
        "55 20 01 41 40 01 00 00 02 3E 81",
        "55 20 01 18 40 3D 00 00 0F 02 01 02 09 02 01 03 08 02 01 07 16 02 01 09 01 03 01 02 09 03 01 03 08 03 01 07 16 03 01 09 01 04 01 01 02 04 01 02 09 04 09 02 01 04 01 03 01 04 09 03 01 04 01 07 01 04 01 0A 17 7E D5",
        "55 20 01 4F 40 01 00 00 01 7E 80",
    ]
    for frame in decoder.feed(captured.flatMap(bytes)) { state.apply(frame) }

    #expect(state.firmware == "1.0.1.74")
    #expect(state.left == Battery(level: 100, charging: false))
    #expect(state.right == Battery(level: 100, charging: false))
    #expect(state.caseBattery == nil)
    #expect(state.noiseMode == .transparency)
    #expect(state.lastANCLevel == .ancAdaptive)
    #expect(state.inEarDetection == true)
    #expect(state.equalizer == .balanced)
    #expect(state.ultraBassEnabled == true)
    #expect(state.ultraBassLevel == 5)
    #expect(state.lowLatency == false)
    #expect(state.spatialAudio == true)
    #expect(state.gestures[GestureKey(bud: .left, gesture: .doubleTap)] == .next)
    #expect(state.gestures[GestureKey(bud: .right, gesture: .hold)] == .noiseANCTransparency)
    #expect(state.gestures.count == 8)
}

@Test func audioModeEventUpdatesMode() {
    var state = BudsState()
    state.apply(Frame(control: 0x0100, command: 0xe003, payload: [0x01, 0x03, 0x00]))
    #expect(state.noiseMode == .ancLow)
    #expect(state.lastANCLevel == .ancLow)
}
