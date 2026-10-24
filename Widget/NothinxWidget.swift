import AppIntents
import NothinxKit
import SwiftUI
import WidgetKit

// Widget extension: noise-control widget and Control Center controls.
// Taps go to the running Nothinx app through WidgetCommand; it talks to the buds.

// MARK: - Intent

/// AppIntents needs the enum declared in this target, so it mirrors NoiseChoice.
enum NoiseOption: String, AppEnum {
    case anc, transparency, off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Noise control mode"
    static let caseDisplayRepresentations: [NoiseOption: DisplayRepresentation] = [
        .anc: DisplayRepresentation(title: "ANC", image: .init(systemName: "waveform.path.ecg")),
        .transparency: DisplayRepresentation(title: "Transparency", image: .init(systemName: "ear.and.waveform")),
        .off: DisplayRepresentation(title: "Off", image: .init(systemName: "speaker.slash")),
    ]

    init(_ choice: NoiseChoice) { self = NoiseOption(rawValue: choice.rawValue)! }
    var choice: NoiseChoice { NoiseChoice(rawValue: rawValue)! }
}

extension NoiseChoice {
    var title: String {
        switch self {
        case .anc: String(localized: "ANC")
        case .transparency: String(localized: "Transparency")
        case .off: String(localized: "Off")
        }
    }

    var symbol: String {
        switch self {
        case .anc: "waveform.path.ecg"
        case .transparency: "ear.and.waveform"
        case .off: "speaker.slash"
        }
    }
}

struct SetNoiseModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Noise control mode"
    static let description = IntentDescription("Switches the earbuds’ noise control through Nothinx.")

    @Parameter(title: "Mode")
    var option: NoiseOption

    init() {}
    init(_ choice: NoiseChoice) { self.option = NoiseOption(choice) }

    func perform() async throws -> some IntentResult {
        let choice = option.choice
        // Show the new mode right away; the app confirms or corrects it once the buds answer.
        if var snapshot = WidgetSnapshot.load(), snapshot.connected {
            snapshot.noiseMode = switch choice {
            case .anc: snapshot.noiseMode.flatMap { $0.isANC ? $0 : nil } ?? .ancAdaptive
            case .transparency: .transparency
            case .off: .off
            }
            snapshot.save()
        }
        WidgetCommand.send(choice)
        return .result()
    }
}

/// Control Center toggles turn their mode on; turning one off falls back to transparency
/// (or to ANC when transparency itself is switched off), like the AirPods module.
struct ToggleNoiseModeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle noise control mode"

    @Parameter(title: "Mode")
    var option: NoiseOption

    @Parameter(title: "On")
    var value: Bool

    init() {}
    init(_ choice: NoiseChoice) { self.option = NoiseOption(choice) }

    func perform() async throws -> some IntentResult {
        let choice = option.choice
        let target: NoiseChoice = value ? choice : (choice == .transparency ? .anc : .transparency)
        return try await SetNoiseModeIntent(target).perform()
    }
}

// MARK: - Widget

struct ControlEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ControlProvider: TimelineProvider {
    static let sample = WidgetSnapshot(
        name: "CMF Buds Pro 2",
        connected: true,
        left: Battery(level: 95, charging: false),
        right: Battery(level: 90, charging: false),
        caseBattery: nil,
        noiseMode: .ancAdaptive
    )

    func placeholder(in context: Context) -> ControlEntry {
        ControlEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ControlEntry) -> Void) {
        completion(ControlEntry(date: .now, snapshot: context.isPreview ? Self.sample : WidgetSnapshot.load() ?? Self.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ControlEntry>) -> Void) {
        // The app reloads the timeline whenever something changes.
        completion(Timeline(entries: [ControlEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

struct ModeButton: View {
    let choice: NoiseChoice
    let selected: Bool
    var compact = false

    var body: some View {
        Button(intent: SetNoiseModeIntent(choice)) {
            Group {
                if compact {
                    HStack(spacing: 8) {
                        Image(systemName: choice.symbol).frame(width: 18)
                        Text(choice.title).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: choice.symbol).font(.system(size: 20, weight: .medium))
                        Text(choice.title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary),
                in: .rect(cornerRadius: compact ? 10 : 16)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ControlWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ControlEntry

    var body: some View {
        let snapshot = entry.snapshot
        let current = snapshot?.noiseMode.map(NoiseChoice.init)
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot)
            if snapshot?.connected == true {
                if family == .systemSmall {
                    VStack(spacing: 5) {
                        ForEach(NoiseChoice.allCases, id: \.self) { choice in
                            ModeButton(choice: choice, selected: choice == current, compact: true)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(NoiseChoice.allCases, id: \.self) { choice in
                            ModeButton(choice: choice, selected: choice == current)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(snapshot == nil ? String(localized: "Open Nothinx") : String(localized: "Earbuds not connected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }

    private func header(_ snapshot: WidgetSnapshot?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "earbuds")
            Text(snapshot?.name ?? "Nothinx").lineLimit(1)
            Spacer(minLength: 4)
            if let snapshot, snapshot.connected {
                Text(batteryText(snapshot)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .semibold))
    }

    private func batteryText(_ snapshot: WidgetSnapshot) -> String {
        let levels = [snapshot.left, snapshot.right].compactMap { $0?.level }
        guard let low = levels.min() else { return "" }
        return "\(low)%"
    }
}

struct NothinxControlWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.nothinx.noise", provider: ControlProvider()) { entry in
            ControlWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Noise Control")
        .description("Switches the earbuds’ noise control mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Control Center

struct NoiseModeValueProvider: ControlValueProvider {
    let choice: NoiseChoice

    var previewValue: Bool { choice == .anc }

    func currentValue() async throws -> Bool {
        guard let mode = WidgetSnapshot.load()?.noiseMode else { return false }
        return NoiseChoice(mode) == choice
    }
}

/// Shared configuration for the three per-mode controls below.
@MainActor
func noiseModeControl(_ choice: NoiseChoice, kind: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind, provider: NoiseModeValueProvider(choice: choice)) { isOn in
        ControlWidgetToggle(choice.title, isOn: isOn, action: ToggleNoiseModeIntent(choice)) { _ in
            Image(systemName: choice.symbol)
        }
        .tint(.accentColor)
    }
    .displayName(LocalizedStringResource(stringLiteral: choice.title))
    .description("Earbuds noise control mode.")
}

struct ANCControl: ControlWidget {
    var body: some ControlWidgetConfiguration { noiseModeControl(.anc, kind: "dev.nothinx.control.anc") }
}

struct TransparencyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        noiseModeControl(.transparency, kind: "dev.nothinx.control.transparency")
    }
}

struct OffControl: ControlWidget {
    var body: some ControlWidgetConfiguration { noiseModeControl(.off, kind: "dev.nothinx.control.off") }
}

@main
struct NothinxWidgets: WidgetBundle {
    var body: some Widget {
        NothinxControlWidget()
        ANCControl()
        TransparencyControl()
        OffControl()
    }
}
