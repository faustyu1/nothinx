# Nothinx

A native macOS menu bar app for Nothing and CMF earbuds. It talks to the earbuds directly over Bluetooth, so the settings normally available only in the Nothing X phone app can be changed from a Mac.

Tested with **CMF Buds Pro 2** (firmware 1.0.1.74). Other Nothing and CMF models share the same protocol and may partly work, but their feature sets differ.

The interface follows the system language; English and Russian are included.

## Features

- Battery level of each earbud and the case
- Noise control: ANC (adaptive, high, medium, low), transparency, off
- Equalizer presets and Ultra Bass with levels 1–5
- Touch gestures per earbud: double tap, triple tap, tap and hold, double tap and hold
- Low latency mode and spatial audio
- In-ear detection with automatic pause: taking an earbud out pauses playback, putting it back resumes it
- Find my earbuds: plays a tone on the chosen earbud
- Connects automatically when the earbuds connect to the Mac; optional launch at login
- Desktop widget and Control Center controls for switching noise control (source builds only, see below)

## Requirements

- macOS 26 or later
- Earbuds paired with the Mac in System Settings → Bluetooth

## Installation

1. Download `Nothinx.zip` from [Releases](../../releases) and move `Nothinx.app` to `/Applications`.
2. The app is not notarized, so macOS blocks the first launch. Remove the quarantine flag:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Nothinx.app
   ```
   or allow it in System Settings → Privacy & Security.
3. Allow Bluetooth access when asked.
4. For automatic pause, allow Nothinx in System Settings → Privacy & Security → Accessibility. It is used to send the Play/Pause media key.

## Building from source

```bash
brew install xcodegen
./build.sh --install
```

The widget and Control Center controls share data with the app through an App Group, which requires signing with your own development team (a free Apple ID in Xcode is enough). Replace `DEVELOPMENT_TEAM` in `project.yml` and the group prefix in `Resources/*.entitlements` and `Sources/NothinxKit/WidgetSnapshot.swift` with your Team ID.

`./release.sh` produces a portable, ad hoc signed `build/Nothinx.zip` without the widget.

Run the protocol tests with:

```bash
swift test
```

## How it works

- `Sources/NothinxKit`: the protocol. Frames are `55 | control | command | length | fsn | payload | crc16`; replies are decoded into `BudsState`.
- `Sources/Nothinx`: the app. An RFCOMM channel through IOBluetooth (`BudsConnection`), the model (`BudsController`), and a SwiftUI panel (`PanelView`).
- `Widget`: the WidgetKit extension with the widget and Control Center controls.

Strings live in String Catalogs (`Localizable.xcstrings`) next to the code of each target. To add a language, add translations to those catalogs and to `Sources/Nothinx/InfoPlist.xcstrings`.

Every frame sent and received is written to the system log:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "dev.nothinx.app"'
```

## Acknowledgements

The protocol is based on the Nothing driver in [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) and was verified against real hardware. Differences found on the CMF Buds Pro 2: adaptive ANC is available, find-my-earbuds addresses each earbud separately, requests must be spaced out, and wear state arrives in event `0xE002`.

This is an unofficial project and is not affiliated with Nothing Technology.

## License

MIT
