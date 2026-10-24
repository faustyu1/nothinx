import AppKit
import CoreAudio

/// Pauses and resumes whatever is playing on the Mac, the way AirPods do when taken out.
/// macOS offers no public "pause" for other apps, so this presses the Play/Pause media key,
/// and only when audio is actually running so the key never starts playback by mistake.
@MainActor
enum MediaControl {
    /// True when the default output device is producing sound for some app.
    static var isPlaying: Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return false
        }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Asks once for permission to post key events; macOS shows its own prompt.
    @discardableResult
    static func ensureAccess() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    static func pressPlayPause() {
        guard ensureAccess() else { return }
        let playKey = 16 // NX_KEYTYPE_PLAY
        for keyDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: keyDown ? 0xa00 : 0xb00)
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (playKey << 16) | ((keyDown ? 0xa : 0xb) << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
