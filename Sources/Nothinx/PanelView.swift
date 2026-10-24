import NothinxKit
import SwiftUI

struct PanelView: View {
    @Bindable var controller: BudsController

    private enum Extra { case gestures, features, settings }

    /// Only one extra section is open at a time so the panel stays short.
    @State private var openExtra: Extra?
    @State private var contentHeight: CGFloat = 0

    private func isOpen(_ extra: Extra) -> Binding<Bool> {
        Binding(
            get: { openExtra == extra },
            set: { openExtra = $0 ? extra : nil }
        )
    }

    /// Leaves room for the menu bar and Dock; the rest scrolls.
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BatteryRow(controller: controller)
                    if controller.isConnected {
                        Divider()
                        NoiseSection(controller: controller)
                        Divider()
                        SoundSection(controller: controller)
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            GesturesSection(controller: controller, expanded: isOpen(.gestures))
                            FeaturesSection(controller: controller, expanded: isOpen(.features))
                            SettingsSection(controller: controller, expanded: isOpen(.settings))
                        }
                    } else {
                        disconnectedHint
                        SettingsSection(controller: controller, expanded: isOpen(.settings))
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, maxHeight - 120))
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .animation(.smooth(duration: 0.25), value: openExtra)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName).font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let firmware = controller.state.firmware, controller.isConnected {
                Text("ПО \(firmware)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var statusText: String {
        switch controller.status {
        case .noDevice: "Наушники не найдены среди сопряжённых"
        case .disconnected: "Не подключены"
        case .connecting: "Подключение…"
        case .connected: "Подключены"
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .connected: .green
        case .connecting: .orange
        default: .secondary
        }
    }

    @ViewBuilder
    private var disconnectedHint: some View {
        if controller.status == .noDevice {
            Text("Сначала подключи наушники к Маку в Настройках → Bluetooth.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Button {
                controller.connect()
            } label: {
                Label("Подключить", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(controller.status == .connecting)
        }
    }

    private var footer: some View {
        HStack {
            Button("Переподключить", systemImage: "arrow.clockwise") { controller.reconnect() }
                .disabled(controller.status == .noDevice)
            Spacer()
            Button("Выйти", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

// MARK: - Battery

private struct BatteryRow: View {
    let controller: BudsController

    var body: some View {
        let live = controller.isConnected
        let state = controller.state
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
            BatteryCell(title: "Левый", symbol: "earbuds", battery: live ? state.left : controller.lastSeenBattery[0])
            BatteryCell(title: "Правый", symbol: "earbuds", battery: live ? state.right : controller.lastSeenBattery[1])
            // The case only reports while a bud sits in it; hide it otherwise.
            if live, let caseBattery = state.caseBattery {
                BatteryCell(title: "Кейс", symbol: "earbuds.case", battery: caseBattery)
            }
            }
        }
        .opacity(live ? 1 : 0.5)
    }
}

private struct BatteryCell: View {
    let title: String
    let symbol: String
    let battery: Battery?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption)
                Text(title).font(.caption)
                if battery?.charging == true {
                    Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.secondary)
            Text(battery.map { "\($0.level)%" } ?? "—")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Gauge(value: Double(battery?.level ?? 0), in: 0...100) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var tint: Color {
        guard let level = battery?.level else { return .secondary }
        return level <= 15 ? .red : level <= 30 ? .orange : .green
    }
}

// MARK: - Noise control

private struct NoiseSection: View {
    let controller: BudsController
    @Namespace private var glass

    var body: some View {
        let mode = controller.state.noiseMode
        VStack(alignment: .leading, spacing: 10) {
            Text("Шумоподавление").font(.subheadline.weight(.semibold))
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ModeButton(title: "Шумодав", symbol: "waveform.path.ecg", selected: mode?.isANC == true) {
                        controller.enableANC()
                    }
                    ModeButton(title: "Прозрачность", symbol: "ear.and.waveform", selected: mode == .transparency) {
                        controller.setNoiseMode(.transparency)
                    }
                    ModeButton(title: "Выкл", symbol: "speaker.slash", selected: mode == .off) {
                        controller.setNoiseMode(.off)
                    }
                }
            }

            if let mode, mode.isANC {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(NoiseMode.ancLevels, id: \.self) { level in
                            Button {
                                controller.setNoiseMode(level)
                            } label: {
                                Text(level.title).font(.caption).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                            .glassEffect(
                                level == mode ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                                in: .capsule
                            )
                            .glassEffectID(level, in: glass)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.25), value: mode)
    }
}

private struct ModeButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 14)
        )
    }
}

// MARK: - Sound

private struct SoundSection: View {
    let controller: BudsController

    var body: some View {
        let state = controller.state
        VStack(alignment: .leading, spacing: 10) {
            Text("Звук").font(.subheadline.weight(.semibold))
            Picker("Эквалайзер", selection: Binding(
                get: { state.equalizer ?? .balanced },
                set: { controller.setEqualizer($0) }
            )) {
                ForEach(EQPreset.allCases, id: \.self) { Text($0.title).tag($0) }
            }

            Toggle("Ultra Bass", isOn: Binding(
                get: { state.ultraBassEnabled ?? false },
                set: { controller.setUltraBass(enabled: $0) }
            ))
            .toggleStyle(.switch)

            if state.ultraBassEnabled == true {
                UltraBassLevels(level: state.ultraBassLevel ?? 3) { controller.setUltraBass(level: $0) }
            }
        }
    }
}

/// One button per level: a write per tap, no drag events to miss.
private struct UltraBassLevels: View {
    let level: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Уровень").font(.caption).foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            onSelect(value)
                        } label: {
                            Text("\(value)")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .foregroundStyle(value == level ? .white : .primary)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            value == level ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                            in: .capsule
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Gestures

private struct GesturesSection: View {
    let controller: BudsController
    @Binding var expanded: Bool
    @State private var bud: Earbud = .left

    var body: some View {
        ExpandableSection(title: "Жесты", symbol: "hand.tap", expanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $bud) {
                    ForEach(Earbud.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ForEach(Gesture.allCases, id: \.self) { gesture in
                    let key = GestureKey(bud: bud, gesture: gesture)
                    LabeledContent(gesture.title) {
                        Picker("", selection: Binding(
                            get: { controller.state.gestures[key] ?? .none },
                            set: { controller.setGesture(key, $0) }
                        )) {
                            ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Features

private struct FeaturesSection: View {
    let controller: BudsController
    @Binding var expanded: Bool

    var body: some View {
        let state = controller.state
        ExpandableSection(title: "Функции", symbol: "slider.horizontal.3", expanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Определение уха", isOn: Binding(
                    get: { state.inEarDetection ?? false },
                    set: { controller.setInEarDetection($0) }
                ))
                Toggle("Низкая задержка", isOn: Binding(
                    get: { state.lowLatency ?? false },
                    set: { controller.setLowLatency($0) }
                ))
                Toggle("Пространственный звук", isOn: Binding(
                    get: { state.spatialAudio ?? false },
                    set: { controller.setSpatialAudio($0) }
                ))
                Text("Найти наушники").padding(.top, 4)
                HStack(spacing: 8) {
                    ForEach(Earbud.allCases, id: \.self) { bud in
                        let ringing = controller.ringing.contains(bud)
                        Button {
                            controller.toggleRinging(bud)
                        } label: {
                            Label(
                                ringing ? "Стоп" : bud.title,
                                systemImage: ringing ? "speaker.slash.fill" : "speaker.wave.3.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(ringing ? .red : .accentColor)
                    }
                }
                Text("Наушник громко пищит, вынь его из уха.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .font(.callout)
            .padding(.top, 6)
        }
    }
}

// MARK: - Settings

private struct SettingsSection: View {
    @Bindable var controller: BudsController
    @Binding var expanded: Bool

    var body: some View {
        ExpandableSection(title: "Настройки", symbol: "gearshape", expanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("В строке меню", selection: $controller.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Запускать при входе", isOn: $controller.launchAtLogin)
                    .toggleStyle(.switch)
            }
            .font(.callout)
            .padding(.top, 6)
        }
    }
}

// MARK: - Expandable section

/// Disclosure row whose whole width is clickable, unlike DisclosureGroup's small chevron.
private struct ExpandableSection<Content: View>: View {
    let title: String
    let symbol: String
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol).frame(width: 20)
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(expanded ? .regular.interactive() : .identity.interactive(), in: .rect(cornerRadius: 12))

            if expanded {
                content
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
