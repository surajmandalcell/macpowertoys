//
//  RcloneWindowView.swift
//  powertoys
//

import SwiftUI
import SwiftData

enum RSyncContent: Hashable {
    case transfers
    case browse(RcloneRemote)
    case activity
    case devSync
    case settings
}

struct RcloneWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = RcloneJobManager.shared
    @State private var content: RSyncContent = .transfers
    @State private var showAddRemote = false
    @AppStorage("rclone.lastContent") private var lastContent = "transfers"
    @AppStorage("rclone.lastFilter") private var lastFilter = JobFilter.all.rawValue
    @State private var windowOwner = UUID()

    var body: some View {
        @Bindable var manager = manager

        HStack(spacing: 0) {
            RcloneSidebarView(content: $content, showAddRemote: $showAddRemote)
                .frame(width: UtilityLayout.dataSidebarWidth)

            contentArea
                .utilityContentTransition(value: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(manager)
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "rclone"))
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("rclone") == true else { return }
            content = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandNewTransfer)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("rclone") == true else { return }
            manager.isPresentingNewTransfer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTransferRequested)) { _ in
            manager.isPresentingNewTransfer = true
        }
        .sheet(isPresented: $manager.isPresentingNewTransfer) {
            NewTransferSheet()
                .environment(manager)
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet()
                .environment(manager)
        }
        .task {
            manager.modelContext = modelContext
            restoreUIState()
            if SettingsManager.shared.isToolEnabled("rclone") {
                await manager.windowDidOpen(owner: windowOwner)
            }
        }
        .onDisappear {
            manager.windowDidClose(owner: windowOwner)
        }
        .onChange(of: content) {
            switch content {
            case .transfers: lastContent = "transfers"
            case .activity: lastContent = "activity"
            case .devSync: lastContent = "devSync"
            case .settings: lastContent = "settings"
            case .browse: lastContent = "transfers"
            }
        }
        .onChange(of: manager.filter) {
            lastFilter = manager.filter.rawValue
        }
    }

    private func restoreUIState() {
        if let filter = JobFilter(rawValue: lastFilter) {
            manager.filter = filter
        }
        switch lastContent {
        case "activity": content = .activity
        case "devSync": content = .devSync
        case "settings": content = .settings
        default: content = .transfers
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch content {
        case .transfers:
            RcloneTransferListView()
        case .browse(let remote):
            RemoteBrowserView(remote: remote)
        case .activity:
            ActivityView()
        case .devSync:
            DevSyncPage()
        case .settings:
            RcloneSettingsPage()
        }
    }
}

#Preview {
    RcloneWindowView()
        .frame(width: 1100, height: 720)
}
