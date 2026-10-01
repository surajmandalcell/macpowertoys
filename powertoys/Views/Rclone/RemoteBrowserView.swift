//
//  RemoteBrowserView.swift
//  powertoys
//

import AppKit
import SwiftUI
import Combine
import QuickLook
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

nonisolated private struct RemoteDisplayEntry: Identifiable, Sendable {
    let entry: RemoteEntry
    let size: String
    let modified: String

    var id: String { entry.path }
}

struct RemoteBrowserView: View {
    private enum SortColumn: Int, Sendable { case name, size, modified }

    let remote: RcloneRemote

    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.isEnabled) private var isEnabled
    @State private var path = ""
    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewURL: URL?
    @State private var selection: Set<String> = []
    @State private var fetchingPreviewName: String?
    @State private var isDropTargeted = false
    @State private var isChoosingUpload = false
    @State private var queuedUploadCount = 0
    @State private var dropToastTask: Task<Void, Never>?
    @State private var isShowingCleanup = false
    @State private var isShowingSettings = false
    @State private var isShowingNewFolder = false
    @State private var newFolderName = ""
    @State private var isCreatingFolder = false
    @State private var folderCreationError: String?
    @State private var sortColumn = SortColumn.name
    @State private var sortAscending = true
    @State private var visibleEntries: [RemoteDisplayEntry] = []
    @State private var sortTask: Task<Void, Never>?

    private var isBusy: Bool {
        !isEnabled || isLoading || isChoosingUpload || isShowingCleanup || isShowingSettings || isShowingNewFolder
            || isCreatingFolder || fetchingPreviewName != nil || manager.isShuttingDown
    }

    private var pathComponents: [String] {
        path.isEmpty ? [] : path.split(separator: "/").map(String.init)
    }

    var body: some View {
        let refresh: (() -> Void)? = isBusy || manager.client == nil ? nil : { Task { await load() } }
        let upload: (() -> Void)? = isBusy || manager.client == nil ? nil : { chooseUpload() }
        let preview: (() -> Void)? = canQuickLook ? { quickLookSelection(selection) } : nil
        let copy: (() -> Void)? = selection.isEmpty || isBusy ? nil : { copyPaths(selection) }
        return OnePlusPage(scrolls: false) {
            header
        } content: {
            contentArea
        }
        .quickLookPreview($previewURL)
        .focusedSceneValue(\.appRefresh, refresh)
        .focusedSceneValue(\.appUpload, upload)
        .focusedSceneValue(\.appQuickLook, preview)
        .focusedSceneValue(\.appCopyPath, copy)
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
            Text(newFolderMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteCleanupCompleted)) { notification in
            guard notification.object as? String == remote.name else { return }
            Task { await load() }
        }
        .task(id: "\(remote.name)|\(path)") { await load() }
        .onChange(of: remote) {
            path = ""
            selection.removeAll()
            errorMessage = nil
            folderCreationError = nil
        }
        .onChange(of: sortColumn) { rebuildVisibleEntries() }
        .onChange(of: sortAscending) { rebuildVisibleEntries() }
        .onDisappear {
            sortTask?.cancel()
            sortTask = nil
            dropToastTask?.cancel()
            dropToastTask = nil
        }
    }

    private var newFolderMessage: String {
        RemoteFolderName.error(for: newFolderName) ?? "Create this folder in \(remote.name):\(path)."
    }

    // MARK: Header

    private var header: some View {
        OnePlusPageHeader(title: remote.displayName, subtitle: remote.typeLabel) {
            Button("Upload") { chooseUpload() }
                .buttonStyle(OnePlusButtonStyle(.neutral))
                .disabled(isBusy || manager.client == nil)
                .help("Drag files and folders from Finder. Save or export Mail and Photos items as local files first.")
            Button("New Folder") {
                newFolderName = ""
                folderCreationError = nil
                isShowingNewFolder = true
            }
            .buttonStyle(OnePlusButtonStyle(.neutral))
            .disabled(isBusy || manager.client == nil)
            Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(OnePlusButtonStyle(.ghost))
                .disabled(isBusy || manager.client == nil)
            OnePlusMenuButton("More remote actions", variant: .borderedIcon, items: [
                .item(.init("Remote Settings…") { isShowingSettings = true }),
                .item(.init("Clean Up by Ignore Rules…") { isShowingCleanup = true })
            ])
        }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                breadcrumbButton(isCurrent: pathComponents.isEmpty, destination: "") {
                    HStack(spacing: 5) {
                        Image(systemName: remote.icon)
                            .onePlusText(.caption)
                        Text(remote.name)
                    }
                }

                ForEach(pathComponents.indices, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.muted)

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
        .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
    }

    // MARK: Content

    private var contentArea: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            if let folderCreationError {
                OnePlusBanner(folderCreationError, tone: .error) {
                    Button("Dismiss") { self.folderCreationError = nil }
                }
            }

            HStack(spacing: OnePlusMetrics.spacing[3]) {
                breadcrumbs
                Spacer(minLength: OnePlusMetrics.spacing[2])
                Text(entries.count == 1 ? "1 item" : "\(entries.count) items")
                    .onePlusText(.mono)
            }
            .frame(height: OnePlusMetrics.controlHeight)
            OnePlusCard {
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
            guard !isBusy else { return false }
            let queued = manager.createDroppedTransfers(urls: urls, remote: remote, directoryPath: path)
            guard queued > 0 else { return false }
            showDropToast(count: queued)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay(alignment: .bottom) { statusFeedback }
    }

    private var entryList: OnePlusNativeTable {
        let rows: [OnePlusTableItem] = visibleEntries.map {
            OnePlusTableItem(id: $0.id, cells: [$0.entry.name, $0.size, $0.modified], symbol: $0.entry.icon)
        }
        let onOpen: ((Set<String>) -> Void)? = selectedEntry == nil || isBusy || manager.client == nil ? nil : { openSelection($0) }
        let onPreview: ((Set<String>) -> Void)? = canQuickLook ? { quickLookSelection($0) } : nil
        return OnePlusNativeTable(
            columns: [
                OnePlusGridColumn("Name", width: 240, textColor: OnePlusColor.ink),
                OnePlusGridColumn("Size", width: 92, trailing: true, textRole: .mono),
                OnePlusGridColumn("Modified", width: 116, trailing: true, textRole: .mono)
            ],
            rows: rows,
            selection: $selection,
            sortColumn: sortColumn.rawValue,
            ascending: sortAscending,
            sort: { column, ascending in
                sortColumn = SortColumn(rawValue: column) ?? .name
                sortAscending = ascending
            },
            open: onOpen,
            preview: onPreview,
            actions: entryActions
        )
    }

    private var selectedEntry: RemoteEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return entries.first { $0.path == id }
    }

    private var canQuickLook: Bool {
        selectedEntry?.isDir == false && !isBusy && manager.client != nil
    }

    private func openSelection(_ ids: Set<String>) {
        guard ids.count == 1, let entry = entries.first(where: { ids.contains($0.path) }) else { return }
        open(entry)
    }

    private func quickLookSelection(_ ids: Set<String>) {
        guard ids.count == 1, let entry = entries.first(where: { ids.contains($0.path) }) else { return }
        quickLook(entry)
    }

    private func copyPaths(_ ids: Set<String>) {
        let paths = visibleEntries.filter { ids.contains($0.id) }.map(\.entry.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    private func entryActions(_ ids: Set<String>) -> [OnePlusTableAction] {
        guard !ids.isEmpty else { return [] }
        var actions: [OnePlusTableAction] = []
        if ids.count == 1, let entry = entries.first(where: { ids.contains($0.path) }) {
            actions.append(OnePlusTableAction(entry.isDir ? "Open" : "Quick Look", enabled: !isBusy && manager.client != nil) {
                open(entry)
            })
        }
        actions.append(OnePlusTableAction(ids.count == 1 ? "Copy Path" : "Copy Paths", enabled: !isBusy) { copyPaths(ids) })
        return actions
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
                    Text("Drop Finder files or folders to upload to \(remote.name):\(path)")
                        .onePlusText(.cardTitle)
                }
            )
            .padding(OnePlusMetrics.spacing[4])
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusFeedback: some View {
        VStack(spacing: 0) {
            if let fetchingPreviewName {
                OnePlusToast("Fetching \(fetchingPreviewName)…", systemImage: "arrow.down.circle")
            }
            if queuedUploadCount > 0 {
                OnePlusToast(queuedUploadCount == 1
                    ? "Transfer queued. View it in Transfers."
                    : "\(queuedUploadCount) transfers queued. View them in Transfers.")
            }
        }
    }

    // MARK: Actions

    private func navigate(to newPath: String) {
        selection.removeAll()
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
        guard !entry.isDir, let client = manager.client else { return nil }
        let item = RemoteFileDragItem(
            client: client,
            srcFs: remote.pathPrefix,
            srcRemote: entry.path,
            fileName: entry.name
        )
        return item.hasValidFileName ? item : nil
    }

    private func pasteboardWriter(for id: String) -> (any NSPasteboardWriting)? {
        guard !isBusy,
              let entry = entries.first(where: { $0.path == id }),
              let item = dragItem(for: entry) else { return nil }
        let delegate = RemoteFilePromiseDelegate(item: item)
        let provider = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: delegate)
        provider.userInfo = delegate
        return provider
    }

    private func showDropToast(count: Int) {
        dropToastTask?.cancel()
        queuedUploadCount = count
        dropToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            queuedUploadCount = 0
        }
    }

    private func chooseUpload() {
        guard !isBusy, manager.client != nil else { return }
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "rclone" }),
              window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        let remote = remote
        let destinationPath = path
        isChoosingUpload = true
        Task {
            defer { isChoosingUpload = false }
            guard await panel.beginSheetModal(for: window) == .OK else { return }
            let queued = manager.createDroppedTransfers(urls: panel.urls, remote: remote, directoryPath: destinationPath)
            if queued > 0 { showDropToast(count: queued) }
        }
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
            rebuildVisibleEntries()
        } catch is CancellationError {
            return
        } catch {
            entries = []
            visibleEntries = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not list folder."
        }
        isLoading = false
    }

    private func rebuildVisibleEntries() {
        sortTask?.cancel()
        let entries = entries
        let sortColumn = sortColumn
        let sortAscending = sortAscending

        sortTask = Task {
            let displayEntries = await Task.detached(priority: .userInitiated) {
                Self.prepare(entries, sortColumn: sortColumn, ascending: sortAscending)
            }.value
            guard !Task.isCancelled else { return }
            visibleEntries = displayEntries
            selection.formIntersection(Set(entries.map(\.path)))
        }
    }

    nonisolated private static func prepare(
        _ entries: [RemoteEntry],
        sortColumn: SortColumn,
        ascending: Bool
    ) -> [RemoteDisplayEntry] {
        let sorted = entries.sorted { left, right in
            let result: ComparisonResult = switch sortColumn {
            case .name: left.name.localizedStandardCompare(right.name)
            case .size: compare(left.size, right.size, tie: left.name.localizedStandardCompare(right.name))
            case .modified: compare(
                left.modTime ?? .distantPast,
                right.modTime ?? .distantPast,
                tie: left.name.localizedStandardCompare(right.name)
            )
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let now = Date()
        return sorted.map {
            RemoteDisplayEntry(
                entry: $0,
                size: $0.isDir ? "" : RcloneProjectionFormat.bytes($0.size),
                modified: $0.modTime.map { formatter.localizedString(for: $0, relativeTo: now) } ?? "Not available"
            )
        }
    }

    nonisolated private static func compare<T: Comparable>(
        _ left: T,
        _ right: T,
        tie: ComparisonResult
    ) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return tie
    }
}

// MARK: - Drag Out

private final class RemoteFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    nonisolated let item: RemoteFileDragItem
    private static let writeQueue = OperationQueue()

    init(item: RemoteFileDragItem) { self.item = item }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        item.fileName
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { Self.writeQueue }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let item = item
        // AppKit permits this completion block on the provider background queue.
        nonisolated(unsafe) let complete = completionHandler
        Task {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("rsync-drag/\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                let file = try await item.download(to: staging)
                try FileManager.default.moveItem(at: file, to: url)
                complete(nil)
            } catch {
                complete(error)
            }
        }
    }
}

nonisolated struct RemoteFileDragItem: Sendable {
    let client: RcloneRCClient
    let srcFs: String
    let srcRemote: String
    let fileName: String

    var hasValidFileName: Bool {
        !fileName.isEmpty && fileName != "." && fileName != ".." && !fileName.contains("/") && !fileName.contains("\0")
    }

    func download(to directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("rsync-drag/\(UUID().uuidString)", isDirectory: true)) async throws -> URL {
        guard hasValidFileName else {
            throw RcloneRCError.decoding("Invalid download file name")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let group = "drag/\(UUID().uuidString)"
        var jobid: Int?
        do {
            let startedJob = try await client.startFileJob(
                srcFs: srcFs, srcRemote: srcRemote,
                dstFs: directory.path, dstRemote: fileName, group: group
            )
            jobid = startedJob
            var consecutiveFailures = 0
            let deadline = Date().addingTimeInterval(900)
            while Date() < deadline {
                try await Task.sleep(for: .milliseconds(250))
                guard let status = try? await client.jobStatus(jobid: startedJob) else {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 20 { throw RcloneRCError.notReachable }
                    continue
                }
                consecutiveFailures = 0
                if status.finished {
                    guard status.success else {
                        throw RcloneRCError.http(status: 0, message: status.error)
                    }
                    await client.deleteStats(group: group)
                    return directory.appendingPathComponent(fileName)
                }
            }
            throw RcloneRCError.http(status: 0, message: "Download timed out.")
        } catch {
            if let jobid { try? await client.stopJob(jobid: jobid) }
            await client.deleteStats(group: group)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
