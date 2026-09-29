//
//  RemoteBrowserView.swift
//  powertoys
//

import AppKit
import SwiftUI
import Combine
import QuickLook
import CoreTransferable
import UniformTypeIdentifiers
import OnePlusUI

nonisolated enum RemoteFolderName {
    static func error(for value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a folder name." }
        guard name != ".", name != ".." else { return "Use a name other than . or .." }
        guard name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\").union(.controlCharacters)) == nil else {
            return "Use a name without slashes or control characters."
        }
        return nil
    }
}

struct RemoteBrowserView: View {
    private enum SortColumn { case name, size, modified }

    let remote: RcloneRemote

    @Environment(RcloneJobManager.self) private var manager
    @State private var path = ""
    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewURL: URL?
    @State private var selection: String?
    @State private var fetchingPreviewName: String?
    @State private var isDropTargeted = false
    @State private var showsDropToast = false
    @State private var dropToastTask: Task<Void, Never>?
    @State private var isShowingCleanup = false
    @State private var isShowingSettings = false
    @State private var isShowingNewFolder = false
    @State private var newFolderName = ""
    @State private var isCreatingFolder = false
    @State private var folderCreationError: String?
    @State private var sortColumn = SortColumn.name
    @State private var sortAscending = true

    private var pathComponents: [String] {
        path.isEmpty ? [] : path.split(separator: "/").map(String.init)
    }

    private var visibleEntries: [RemoteEntry] {
        entries.sorted { left, right in
            let result: ComparisonResult = switch sortColumn {
            case .name: left.name.localizedStandardCompare(right.name)
            case .size: compare(left.size, right.size, tie: left.name.localizedStandardCompare(right.name))
            case .modified: compare(
                left.modTime ?? .distantPast,
                right.modTime ?? .distantPast,
                tie: left.name.localizedStandardCompare(right.name)
            )
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func compare<T: Comparable>(_ left: T, _ right: T, tie: ComparisonResult) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return tie
    }

    var body: some View {
        OnePlusPage(scrolls: false) {
            header
        } content: {
            contentArea
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $isShowingCleanup) {
            CleanupRemoteSheet(remote: remote, startPath: path)
        }
        .sheet(isPresented: $isShowingSettings) { RemoteSettingsSheet(remote: remote) }
        .alert("New Folder", isPresented: $isShowingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create Folder") { createFolder() }
                .keyboardShortcut(.defaultAction)
                .disabled(RemoteFolderName.error(for: newFolderName) != nil)
        } message: {
            Text(RemoteFolderName.error(for: newFolderName) ?? "Create this folder in \(remote.name):\(path).")
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteCleanupCompleted)) { notification in
            guard notification.object as? String == remote.name else { return }
            Task { await load() }
        }
        .task(id: "\(remote.name)|\(path)") { await load() }
        .onChange(of: remote) {
            path = ""
            selection = nil
            errorMessage = nil
            folderCreationError = nil
        }
    }

    // MARK: Header

    private var header: some View {
        OnePlusPageHeader(title: remote.displayName, subtitle: remote.typeLabel) {
            Button("Upload") { chooseUpload() }
                .buttonStyle(OnePlusButtonStyle(.neutral))
            Button("New Folder") {
                newFolderName = ""
                folderCreationError = nil
                isShowingNewFolder = true
            }
            .buttonStyle(OnePlusButtonStyle(.neutral))
            .disabled(isCreatingFolder)
            Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(OnePlusButtonStyle(.ghost))
                .disabled(isLoading)
            Menu {
                Button("Remote Settings…") { isShowingSettings = true }
                Button("Clean Up by Ignore Rules…") { isShowingCleanup = true }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More remote actions")
        }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                breadcrumbButton(isCurrent: pathComponents.isEmpty, destination: "") {
                    HStack(spacing: 5) {
                        Image(systemName: remote.icon)
                            .font(.system(size: 11))
                        Text(remote.name)
                    }
                }

                ForEach(Array(pathComponents.indices), id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    let isCurrent = index == pathComponents.count - 1
                    breadcrumbButton(
                        isCurrent: isCurrent,
                        destination: pathComponents[...index].joined(separator: "/")
                    ) {
                        Text(pathComponents[index])
                    }
                }
            }
        }
        .thinScrollIndicators()
    }

    private func breadcrumbButton<Label: View>(
        isCurrent: Bool,
        destination: String,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            guard path != destination else { return }
            navigate(to: destination)
        } label: {
            label()
                .onePlusText(isCurrent ? .cardTitle : .row)
                .foregroundStyle(isCurrent ? AnyShapeStyle(OnePlusColor.ink) : AnyShapeStyle(OnePlusColor.secondary))
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: Content

    private var contentArea: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            if let folderCreationError {
                OnePlusBanner(folderCreationError, tone: .error) {
                    Button("Dismiss") { self.folderCreationError = nil }
                }
            }

            OnePlusCard {
                OnePlusCardHeader("Path") {
                    breadcrumbs
                    Spacer(minLength: OnePlusMetrics.spacing[2])
                    Text(entries.count == 1 ? "1 item" : "\(entries.count) items")
                        .onePlusText(.mono)
                        .foregroundStyle(OnePlusColor.muted)
                }
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else if entries.isEmpty {
                        OnePlusEmptyState("Empty folder", systemImage: "folder")
                    } else {
                        entryList
                    }

                    if isDropTargeted {
                        dropOverlay
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { (urls: [URL], _: CGPoint) in
            manager.createDroppedTransfers(urls: urls, remote: remote, directoryPath: path)
            showDropToast()
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay(alignment: .bottom) { statusChips }
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sortButton("Name", column: .name).frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Size", column: .size).frame(width: 92, alignment: .trailing)
                sortButton("Modified", column: .modified).frame(width: 116, alignment: .trailing)
            }
            .onePlusTableHeader()
            ScrollView {
                LazyVStack(spacing: 0) {
                ForEach(visibleEntries) { entry in
                    RemoteEntryRow(
                        entry: entry,
                        isSelected: selection == entry.id,
                        dragItem: dragItem(for: entry),
                        onSelect: { selection = entry.id },
                        onOpen: { open(entry) },
                        onQuickLook: { quickLook(entry) }
                    )
                }
            }
            }
            .onePlusScrollIndicators()
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let selection,
                  let entry = entries.first(where: { $0.id == selection }),
                  !entry.isDir else { return .ignored }
            quickLook(entry)
            return .handled
        }
    }

    private func sortButton(_ title: String, column: SortColumn) -> some View {
        Button {
            if sortColumn == column { sortAscending.toggle() }
            else { sortColumn = column; sortAscending = true }
        } label: {
            HStack(spacing: OnePlusMetrics.spacing[1]) {
                Text(title.uppercased())
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(sortColumn == column ? (sortAscending ? "Ascending" : "Descending") : "Not sorted")
    }

    private func errorState(_ message: String) -> some View {
        OnePlusEmptyState(message, systemImage: "exclamationmark.triangle") {
            Button("Retry") { Task { await load() } }
                .buttonStyle(OnePlusButtonStyle(.neutral))
        }
    }

    // MARK: Drop feedback

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius)
            .fill(OnePlusColor.selection)
            .overlay(
                RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius)
                    .strokeBorder(OnePlusColor.focus, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .overlay(
                VStack(spacing: OnePlusMetrics.spacing[3]) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(OnePlusColor.ink)
                    Text("Drop to upload to \(remote.name):\(path)")
                        .onePlusText(.cardTitle)
                }
            )
            .padding(OnePlusMetrics.spacing[4])
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusChips: some View {
        VStack(spacing: OnePlusMetrics.spacing[2]) {
            if let fetchingPreviewName {
                chip {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching \(fetchingPreviewName)…")
                        .onePlusText(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if showsDropToast {
                chip {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OnePlusColor.ok)
                    Text("Transfer queued. View it in Transfers.")
                        .onePlusText(.caption)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, OnePlusMetrics.spacing[4])
        .allowsHitTesting(false)
    }

    private func chip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: OnePlusMetrics.spacing[3]) {
            content()
        }
        .padding(.horizontal, OnePlusMetrics.spacing[4])
        .frame(height: OnePlusMetrics.controlHeight)
        .background(OnePlusColor.raised, in: Capsule())
        .overlay { Capsule().strokeBorder(OnePlusColor.line) }
    }

    // MARK: Actions

    private func navigate(to newPath: String) {
        selection = nil
        errorMessage = nil
        path = newPath
    }

    private func open(_ entry: RemoteEntry) {
        if entry.isDir {
            navigate(to: entry.path)
        } else {
            quickLook(entry)
        }
    }

    private func quickLook(_ entry: RemoteEntry) {
        guard !entry.isDir, fetchingPreviewName == nil else { return }
        fetchingPreviewName = entry.name
        Task {
            do {
                previewURL = try await manager.downloadForPreview(remote: remote, entry: entry)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not fetch preview."
            }
            fetchingPreviewName = nil
        }
    }

    private func dragItem(for entry: RemoteEntry) -> RemoteFileDragItem? {
        guard !entry.isDir, let port = manager.daemonPort else { return nil }
        return RemoteFileDragItem(
            port: port,
            srcFs: remote.pathPrefix,
            srcRemote: entry.path,
            fileName: entry.name
        )
    }

    private func showDropToast() {
        dropToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showsDropToast = true }
        dropToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showsDropToast = false }
        }
    }

    private func chooseUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        manager.createDroppedTransfers(urls: panel.urls, remote: remote, directoryPath: path)
        showDropToast()
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteFolderName.error(for: name) == nil else { return }
        let destination = path.isEmpty ? name : "\(path)/\(name)"
        isCreatingFolder = true
        folderCreationError = nil
        Task {
            defer { isCreatingFolder = false }
            do {
                try await manager.createDirectory(remote: remote, path: destination)
                await load()
            } catch {
                folderCreationError = "Unable to create \"\(name)\". \(error.localizedDescription)"
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await manager.listDirectory(remote: remote, path: path)
        } catch is CancellationError {
            return
        } catch {
            entries = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not list folder."
        }
        isLoading = false
    }
}

// MARK: - Entry Row

private struct RemoteEntryRow: View {
    let entry: RemoteEntry
    let isSelected: Bool
    let dragItem: RemoteFileDragItem?
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onQuickLook: () -> Void

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        if let dragItem {
            row.draggable(dragItem)
        } else {
            row
        }
    }

    private var row: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: entry.icon)
                    .foregroundStyle(OnePlusColor.secondary)
                    .frame(width: OnePlusMetrics.navIcon)

                Text(entry.name)
                    .onePlusText(.row)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if !entry.isDir && (isHovering || isSelected) {
                    quickLookButton
                }

                if !entry.isDir {
                    Text(RcloneFormat.bytes(entry.size))
                        .onePlusText(.mono)
                        .foregroundStyle(OnePlusColor.secondary)
                        .frame(width: 92, alignment: .trailing)
                }

                Text(modTimeText)
                    .onePlusText(.mono)
                    .foregroundStyle(OnePlusColor.muted)
                    .frame(width: 116, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onePlusTableRow(selected: isSelected)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(entry.isDir ? "Open" : "Quick Look") { entry.isDir ? onOpen() : onQuickLook() }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            }
        }
    }

    private var quickLookButton: some View {
        Button(action: onQuickLook) {
            Image(systemName: "eye")
                .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        .focusEffectDisabled()
        .help("Quick Look")
    }

    private var modTimeText: String {
        guard let modTime = entry.modTime else { return "Not available" }
        return Self.relativeFormatter.localizedString(for: modTime, relativeTo: Date())
    }
}

// MARK: - Drag Out

nonisolated struct RemoteFileDragItem: Transferable, Sendable {
    let port: Int
    let srcFs: String
    let srcRemote: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { item in
            let client = RcloneRCClient(port: item.port)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("rsync-drag/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let jobid = try await client.startCopyFileJob(
                srcFs: item.srcFs,
                srcRemote: item.srcRemote,
                dstFs: directory.path,
                dstRemote: item.fileName,
                group: "drag/\(UUID().uuidString)"
            )
            do {
                var consecutiveFailures = 0
                while true {
                    try await Task.sleep(for: .milliseconds(250))
                    guard let status = try? await client.jobStatus(jobid: jobid) else {
                        consecutiveFailures += 1
                        if consecutiveFailures >= 20 { throw RcloneRCError.notReachable }
                        continue
                    }
                    consecutiveFailures = 0
                    if status.finished {
                        if status.success { break }
                        throw RcloneRCError.http(status: 0, message: status.error)
                    }
                }
            } catch {
                try? await client.stopJob(jobid: jobid)
                throw error
            }
            return SentTransferredFile(directory.appendingPathComponent(item.fileName), allowAccessingOriginalFile: true)
        }
    }
}
