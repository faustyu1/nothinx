import NothinxKit
import SwiftUI

@main
struct NothinxApp: App {
    @State private var controller = BudsController()

    var body: some Scene {
        MenuBarExtra {
            PanelView(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let controller: BudsController

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: controller.isConnected ? "earbuds" : "earbuds.case")
            if controller.isConnected, let text {
                Text(text)
            }
        }
    }

    private var text: String? {
        switch controller.menuBarDisplay {
        case .icon: nil
        case .battery: controller.lowestBudBattery.map { "\($0)%" }
        case .mode:
            switch controller.state.noiseMode {
            case .some(let mode) where mode.isANC: "ANC"
            case .transparency: "Прозр."
            case .off: "Выкл"
            default: nil
            }
        }
    }
}
