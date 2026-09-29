//
//  RcloneWindowView.swift
//  powertoys
//

import SwiftUI
import SwiftData
import OnePlusUI

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

        OnePlusWindowRoot(canvas: .rclone) {
            RcloneSidebarView(content: $content, showAddRemote: $showAddRemote)
        } content: {
            contentArea.utilityContentTransition(value: content)
        }
        .environment(manager)
        .buttonStyle(OnePlusButtonStyle())
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
            DevSyncManager.shared.engine = DevSyncService.shared
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
        .onOpenToolPage("rclone") { open(page: $0) }
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

    private func open(page: String) {
        if let filter = JobFilter.allCases.first(where: { $0.rawValue == page }) {
            manager.filter = filter
            content = .transfers
            return
        }
        switch page {
        case "activity": content = .activity
        case "dev-sync": content = .devSync
        case "settings": content = .settings
        case "new-transfer": manager.isPresentingNewTransfer = true
        default:
            guard page.hasPrefix("remote/") else { return }
            let name = String(page.dropFirst("remote/".count))
            if let remote = manager.remotes.first(where: { $0.name == name }) {
                content = .browse(remote)
            }
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
}
