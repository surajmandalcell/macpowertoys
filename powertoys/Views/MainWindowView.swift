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

            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.backgroundColor = .clear
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    MainWindowView()
        .environmentObject(ProjectManager())
        .environmentObject(BookmarkManager())
        .environmentObject(SelectionManager())
}
