import SwiftUI
import OnePlusUI

struct RowAndTabStatesShowcase: View {
    @State private var tab = "all"
    @State private var segment = "Default"
    @State private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([OnePlusControlState.rest, .hover], id: \.self) { state in
                OnePlusCard {
                    OnePlusCardHeader(state == .hover ? "Hover" : "Rest", subtitle: "Tabs and complete rows")
                    OnePlusTabStrip(tabs: [.init("all", "All tools", count: 14, countDigits: 0),
                                          .init("enabled", "Enabled", count: 14, countDigits: 0),
                                          .init("favorites", "Favorites", count: 0, countDigits: 0)], selection: $tab)
                    OnePlusSettingRow("History", caption: "Keep recent activity", separator: false) {
                        Toggle("History", isOn: $enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    }
                    HStack {
                        Text("Workstation")
                        Spacer()
                        OnePlusSparkline(values: [1, 3, 2, 4]).frame(width: 80, height: 16)
                        Text("42 MB").onePlusText(.mono)
                        Button("Open") {}.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    }.onePlusTableRow()
                    OnePlusDeviceNavRow("External disk", subtitle: "/Volumes/Work", systemImage: "externaldrive",
                                        selected: false, locked: false, action: {}) {
                        Button {} label: { Image(systemName: "eject") }
                            .buttonStyle(OnePlusButtonStyle(.icon, size: .small)).padding(.trailing, 10)
                            .help("Eject").accessibilityLabel("Eject")
                    }
                }.environment(\.onePlusControlState, state)
            }
            OnePlusSegmented(choices: ["Default", "On", "Off"].map { ($0, $0) }, selection: $segment)
                .environment(\.onePlusControlState, .hover)
            HStack(alignment: .top, spacing: 16) {
                OnePlusMenuTile(span: 2, height: 51, textured: false, action: {}) {
                    HStack { Text("Single centered row").onePlusText(.row); Spacer(); Text("12 GB").onePlusText(.mono) }
                }.historyBackground(values: [15, 40, 20, 70, 45])
                OnePlusMenuControlRow("Awake", systemImage: "moon.zzz", caption: "Keep this Mac awake") {
                    Toggle("Awake", isOn: $enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }.environment(\.onePlusControlState, .hover)
            }
            OnePlusMenuItemCard("Workstation", status: "Connected", metrics: [
                .init("CPU", value: "24", unit: "%"), .init("Memory", value: "12", unit: "GB")
            ]) {
                OnePlusSparkline(values: [1, 3, 2, 4]).frame(height: 24)
            } actions: {
                Button("Open SSH") {}
                Button("Open App") {}
            }.environment(\.onePlusControlState, .hover)
        }
    }
}
