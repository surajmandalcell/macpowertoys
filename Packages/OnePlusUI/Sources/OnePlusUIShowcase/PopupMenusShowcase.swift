import OnePlusUI
import SwiftUI

struct PopupMenusShowcase: View {
    @State private var regularSelection = "Automatic"
    @State private var compactSelection = "Automatic"
    @State private var lastAction = "No action selected"

    private let longChoices = [
        "Automatic", "Every minute", "Every 2 minutes", "Every 5 minutes",
        "Every 10 minutes", "Every 15 minutes", "Every 20 minutes", "Every 30 minutes",
        "Hourly", "Every 2 hours", "Every 3 hours", "Every 4 hours",
        "Every 6 hours", "Every 8 hours", "Every 12 hours", "Daily",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusBanner("Open each control with a click, Space, Return, or Down Arrow. Escape returns focus to its trigger.")
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                samples(title: "Regular density", selection: $regularSelection)
                    .onePlusDensity(.regular)
                samples(title: "Compact density", selection: $compactSelection)
                    .onePlusDensity(.compact)
            }
            OnePlusCard {
                OnePlusCardHeader("Last action")
                Text(lastAction).onePlusText(.row).padding(OnePlusMetrics.cardPadding)
            }
        }
    }

    private func samples(title: String, selection: Binding<String>) -> some View {
        OnePlusCard {
            OnePlusCardHeader(title)
            OnePlusSettingRow("Long select") {
                OnePlusSelect(choices: longChoices.map { ($0, $0) }, selection: selection,
                              width: OnePlusMetrics.wideControlColumn,
                              accessibilityLabel: "Refresh interval")
                    .accessibilityIdentifier("showcase.popup.\(title == "Regular density" ? "regular" : "compact")")
            }
            OnePlusSettingRow("Ghost menu") {
                OnePlusMenuButton("More", items: actionItems)
            }
            OnePlusSettingRow("Neutral menu") {
                OnePlusMenuButton("Export", variant: .neutral, items: actionItems)
            }
            OnePlusSettingRow("SwiftUI commands", separator: false) {
                OnePlusActionMenu("More") {
                    Button("Copy sample") { lastAction = "Copied sample" }
                    Button("Unavailable") {}.disabled(true)
                    Divider()
                    Menu("Export") {
                        Button("Archive") { lastAction = "Export archive" }
                        Button("Text") { lastAction = "Export text" }
                    }
                }
            }
        }
    }

    private var actionItems: [OnePlusPopupMenuEntry] {
        [
            .section("File actions"),
            .item(OnePlusPopupMenuItem("Export archive", systemImage: "archivebox") {
                lastAction = "Export archive"
            }),
            .item(OnePlusPopupMenuItem("Copy link", systemImage: "link") {
                lastAction = "Copy link"
            }),
            .item(OnePlusPopupMenuItem("Unavailable action", systemImage: "lock", isEnabled: false) {}),
            .separator(),
            .section("Danger zone"),
            .item(OnePlusPopupMenuItem("Remove sample", systemImage: "trash", role: .destructive) {
                lastAction = "Remove sample"
            }),
        ]
    }
}
