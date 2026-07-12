//
//  RcloneWindowView.swift
//  powertoys
//

import SwiftUI
import SwiftData

enum RSyncContent: Equatable {
    case transfers
    case browse(RcloneRemote)
    case activity
    case settings
}

struct RcloneWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = RcloneJobManager.shared
    @State private var content: RSyncContent = .transfers
    @State private var showAddRemote = false

    var body: some View {
        @Bindable var manager = manager

        HStack(spacing: 0) {
            RcloneSidebarView(content: $content, showAddRemote: $showAddRemote)
                .frame(width: 264)

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(manager)
        .ignoresSafeArea()
        .background(WindowAccessor())
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
            await manager.start()
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
        case .settings:
            RcloneSettingsPage()
        }
    }
}

#Preview {
    RcloneWindowView()
        .frame(width: 1100, height: 720)
}
