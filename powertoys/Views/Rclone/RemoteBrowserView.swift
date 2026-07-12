//
//  RemoteBrowserView.swift
//  powertoys
//

import SwiftUI
import QuickLook
import CoreTransferable
import UniformTypeIdentifiers

struct RemoteBrowserView: View {
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

    private var pathComponents: [String] {
        path.isEmpty ? [] : path.split(separator: "/").map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .quickLookPreview($previewURL)
        .task(id: "\(remote.name)|\(path)") { await load() }
        .onChange(of: remote) {
            path = ""
            selection = nil
            errorMessage = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            breadcrumbs

            Spacer(minLength: 12)

            Text(entries.count == 1 ? "1 item" : "\(entries.count) items")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Refresh")
            .disabled(isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.top, 52)
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: Content

    private var contentArea: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if entries.isEmpty {
                EmptyStateView(icon: "folder", message: "Empty folder")
            } else {
                entryList
            }

            if isDropTargeted {
                dropOverlay
            }
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
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 1) {
                ForEach(entries) { entry in
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
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

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "exclamationmark.triangle", message: message)
            Button {
                Task { await load() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
    }

    // MARK: Drop feedback

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.accentColor.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop to upload to \(remote.name):\(path)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            )
            .padding(12)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusChips: some View {
        VStack(spacing: 6) {
            if let fetchingPreviewName {
                chip {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching \(fetchingPreviewName)…")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if showsDropToast {
                chip {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Transfer queued — see Transfers")
                        .font(.system(size: 11))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 14)
        .allowsHitTesting(false)
    }

    private func chip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
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
                    .font(.system(size: 14))
                    .foregroundStyle(entry.isDir ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 22)

                Text(entry.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if !entry.isDir && (isHovering || isSelected) {
                    quickLookButton
                }

                if !entry.isDir {
                    Text(RcloneFormat.bytes(entry.size))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(modTimeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.1) }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var quickLookButton: some View {
        Button(action: onQuickLook) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Quick Look")
    }

    private var modTimeText: String {
        guard let modTime = entry.modTime else { return "—" }
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
