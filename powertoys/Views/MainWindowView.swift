//
//  MainWindowView.swift
//  powertoys
//

import SwiftUI

struct MainWindowView: View {
    @State private var selectedTool: String? = "all-tools"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            ToolSidebarView(selectedTool: $selectedTool)
                .frame(width: 220)

            ZStack(alignment: .topLeading) {
                contentView
                    .padding(.top, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .frame(width: 780, height: 700)
        .background(WindowAccessor())
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCategory)) { notification in
            if let category = notification.object as? ToolCategory {
                selectedTool = category == .all ? "all-tools" : ToolRegistry.tools(for: category).first?.id
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTool {
        case "all-tools":
            AllToolsGridView(selectedTool: $selectedTool)
        case "settings":
            SettingsView()
        case let toolId?:
            ToolSettingsView(toolId: toolId, openWindow: openWindow)
        default:
            ContentUnavailableView("Select a Tool", systemImage: "wrench.adjustable", description: Text("Choose a tool from the sidebar."))
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            WindowStateManager.shared.restoreState(for: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    MainWindowView()
}
