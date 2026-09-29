import OnePlusUI
import SwiftUI

struct SidebarRow: View {
    let icon: String
    let title: String
    var isSelected = false
    var logoAsset: String? = nil
    var customSelectionColor: Color? = nil
    let action: () -> Void
    @Environment(\.toolWindowID) private var windowID

    var body: some View {
        row
            .onAppear(perform: deliverMainPage)
            .onReceive(NotificationCenter.default.publisher(for: .openToolPage)) { _ in deliverMainPage() }
    }

    private var row: some View {
        OnePlusNavRow(title, systemImage: icon,
                      image: logoAsset.flatMap { $0.isEmpty ? nil : Image($0) },
                      selected: isSelected, action: action)
    }

    private func deliverMainPage() {
        guard windowID == "main" else { return }
        // ponytail: legacy rows identify tools by title; pass tool IDs when ToolSidebarView adopts page routing.
        let page = title == "All Tools" ? "all-tools" : ToolRegistry.allTools.first { $0.name == title }?.id
        guard let page, ToolPageRouter.shared.take(tool: "main", matching: page) != nil else { return }
        action()
    }
}

struct SidebarExternalRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    var body: some View { OnePlusNavRow(title, systemImage: icon, external: true, action: action) }
}
