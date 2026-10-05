import OnePlusUI
import SwiftUI

struct PartitionSheetRequest: Identifiable {
    enum Kind {
        case rename, format, delete, eraseDisk, firstAid, info
        case confirm(PartitionOperation)

        init(_ action: PartitionAction) {
            self = switch action {
            case .rename: .rename
            case .format: .format
            case .delete: .delete
            case .eraseDisk: .eraseDisk
            case .firstAid: .firstAid
            default: .info
            }
        }
    }
    let id = UUID()
    let kind: Kind
    let disk: ManagedDisk
    let selection: PartitionSelection
}

/// Collects the inputs for one operation, names the exact disk, and confirms before anything runs.
struct PartitionOperationSheet: View {
    let model: DiskManagementModel
    let request: PartitionSheetRequest
    let close: () -> Void
    @State private var name = "Untitled"
    @State private var system = PartitionFileSystem.exfat
    @State private var scheme = PartitionScheme.gpt
    @State private var typedName = ""
    @State private var details: [(String, String)] = []
    @State private var detailError: String?

    private var disk: ManagedDisk { request.disk }
    private var partition: ManagedPartition? {
        switch request.selection {
        case .partition(_, let id), .volume(_, let id, _): disk.partitions.first { $0.id == id }
        default: nil
        }
    }
    private var volume: ManagedVolume? {
        guard case .volume(_, _, let id) = request.selection else { return nil }
        return partition?.volumes.first { $0.id == id }
    }
    private var targetID: String? { volume?.id ?? partition?.id }
    /// An APFS container renames through its one volume.
    private var renameTarget: String? {
        volume?.id ?? (partition?.isAPFS == true ? partition?.volumes.first?.id : partition?.id)
    }

    var body: some View {
        OnePlusSheet(title, width: .medium) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                identity
                fields
                if let warning { OnePlusBanner(warning, tone: .warning) }
                if let error = operationError { Text(error).onePlusText(.caption, color: OnePlusColor.danger) }
            }
        } footer: {
            Button("Cancel", action: close).buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
            footerActions
        }
        .onAppear(perform: prepare)
    }

    private var title: String {
        switch request.kind {
        case .rename: "Rename \(volume?.name ?? partition?.displayName ?? disk.name)"
        case .format: "Format \(partition?.displayName ?? "partition")"
        case .delete: "Delete \(partition?.displayName ?? "partition")"
        case .eraseDisk: "Erase \(disk.name)"
        case .firstAid: "First Aid"
        case .info: "Info"
        case .confirm(let operation): operation.title
        }
    }

    private var identity: some View {
        VStack(spacing: 0) {
            OnePlusKeyValueRow("Disk", value: disk.name)
            OnePlusKeyValueRow("Identifier", value: "/dev/\(disk.id)", monospaced: true)
            OnePlusKeyValueRow("Disk size", value: "\(disk.size.diskSize) (\(disk.size.formatted()) bytes)", monospaced: true)
            if let partition {
                OnePlusKeyValueRow("Target", value: "/dev/\(targetID ?? partition.id) · \(volume?.name ?? partition.displayName) · \(partition.displayFileSystem) · \(partition.size.diskSize)",
                                   monospaced: true)
            }
        }.accessibilityIdentifier("partitions.sheet.identity")
    }

    @ViewBuilder private var fields: some View {
        switch request.kind {
        case .rename:
            OnePlusSettingRow("Name", controlWidth: OnePlusMetrics.wideControlColumn) { OnePlusTextField("Name", text: $name) }
                .environment(\.onePlusCardPadding, 0)
        case .format:
            OnePlusSettingRow("Name", controlWidth: OnePlusMetrics.wideControlColumn) { OnePlusTextField("Name", text: $name) }
                .environment(\.onePlusCardPadding, 0)
            OnePlusSettingRow("File system", controlWidth: OnePlusMetrics.wideControlColumn) {
                OnePlusSelect(choices: systems(gpt: disk.scheme == "GUID_partition_scheme"), selection: $system,
                              width: OnePlusMetrics.wideControlColumn, accessibilityLabel: "File system")
            }.environment(\.onePlusCardPadding, 0)
        case .eraseDisk:
            OnePlusSettingRow("Name", controlWidth: OnePlusMetrics.wideControlColumn) { OnePlusTextField("Name", text: $name) }
                .environment(\.onePlusCardPadding, 0)
            OnePlusSettingRow("File system", controlWidth: OnePlusMetrics.wideControlColumn) {
                OnePlusSelect(choices: systems(gpt: scheme == .gpt), selection: $system,
                              width: OnePlusMetrics.wideControlColumn, accessibilityLabel: "File system")
            }.environment(\.onePlusCardPadding, 0)
            OnePlusSettingRow("Partition map", controlWidth: OnePlusMetrics.wideControlColumn) {
                OnePlusSelect(choices: PartitionScheme.allCases.map { ($0, $0.title) }, selection: $scheme,
                              width: OnePlusMetrics.wideControlColumn, accessibilityLabel: "Partition map")
            }.environment(\.onePlusCardPadding, 0)
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                Text("Type \(disk.name) to confirm.").onePlusText(.row)
                OnePlusTextField(disk.name, text: $typedName).accessibilityIdentifier("partitions.confirmName")
            }
        case .confirm(let operation):
            Text(confirmSummary(operation)).onePlusText(.row).fixedSize(horizontal: false, vertical: true)
        case .info:
            if details.isEmpty && detailError == nil { ProgressView("Reading details...").controlSize(.small) }
            if let detailError { Text(detailError).onePlusText(.caption, color: OnePlusColor.danger) }
            VStack(spacing: 0) {
                ForEach(details, id: \.0) { key, value in OnePlusKeyValueRow(key, value: value, monospaced: true) }
            }.textSelection(.enabled)
        case .firstAid:
            Text(targetID == nil ? "Verify checks the partition map of the whole disk. It does not change the disk." :
                 "Verify checks the file system without changes. Repair fixes errors it finds. Keep a backup before you repair.")
                .onePlusText(.row).fixedSize(horizontal: false, vertical: true)
        case .delete:
            EmptyView()
        }
    }

    @ViewBuilder private var footerActions: some View {
        switch request.kind {
        case .info:
            EmptyView()
        case .firstAid:
            if let targetID {
                Button("Repair") { run(.repair(target: targetID)) }.buttonStyle(OnePlusButtonStyle())
                    .disabled(disk.protectionReason != nil).help(disk.protectionReason ?? "Repair the file system")
            }
            Button("Verify") { run(.verify(target: targetID)) }.buttonStyle(OnePlusButtonStyle(.primary))
        default:
            if let operation {
                Button(operation.title, role: operation.isDestructive ? .destructive : nil) { run(operation) }
                    .buttonStyle(OnePlusButtonStyle(operation.isDestructive ? .destructive : .primary))
                    .disabled(!canRun).accessibilityIdentifier("partitions.sheet.run")
            }
        }
    }

    private var operation: PartitionOperation? {
        switch request.kind {
        case .rename: renameTarget.map { .rename(target: $0, name: name) }
        case .format: partition.map { .format(target: $0.id, fileSystem: system, name: name) }
        case .delete: partition.map { .delete(target: $0.id) }
        case .eraseDisk: .eraseDisk(fileSystem: system, name: name, scheme: scheme)
        case .confirm(let operation): operation
        case .info, .firstAid: nil
        }
    }
    private var operationError: String? {
        guard let operation, !name.isEmpty else { return nil }
        do { _ = try operation.arguments(on: disk); return nil } catch { return error.localizedDescription }
    }
    private var canRun: Bool {
        guard let operation, !model.isBusy, !model.isPreview, operationError == nil else { return false }
        if operation.isWrite && disk.protectionReason != nil { return false }
        if case .eraseDisk = operation { return typedName == disk.name }
        return true
    }
    private var warning: String? {
        switch operation {
        case .format?: "Formatting erases every file on this partition."
        case .delete?: "Deleting removes this partition and every file on it. Its space becomes unallocated."
        case .eraseDisk?: "Erasing replaces the partition map and removes every partition and file on \(disk.name)."
        case .resize?: "Resizing changes the partition map. Keep a backup before you continue."
        default: nil
        }
    }
    private func confirmSummary(_ operation: PartitionOperation) -> String {
        switch operation {
        case .resize(let target, let size, let split):
            let current = disk.partitions.first { $0.id == target }?.size ?? 0
            let added = split.map { " A new \($0.fileSystem.title) partition named \($0.name) fills the freed space." } ?? ""
            return "/dev/\(target) changes from \(current.diskSize) to \(size.diskSize).\(added)"
        case .create(_, let system, let name, let size):
            return "A new \(system.title) partition named \(name) uses \(size?.diskSize ?? "all") of the unallocated space."
        default:
            return operation.title
        }
    }
    private func systems(gpt: Bool) -> [(PartitionFileSystem, String)] {
        PartitionFileSystem.allCases.filter { $0 != .apfs || gpt }.map { ($0, $0.title) }
    }
    private func prepare() {
        name = volume?.name ?? partition.map { $0.isAPFS ? ($0.volumes.first?.name ?? "Untitled") : $0.name } ?? "Untitled"
        if name.isEmpty { name = "Untitled" }
        if let type = partition?.fileSystemType {
            system = switch type { case "apfs": .apfs; case "hfs": .hfs; case "msdos": .fat32; default: .exfat }
        }
        if case .eraseDisk = request.kind { system = .exfat; name = "Untitled" }
        guard case .info = request.kind else { return }
        let id = targetID ?? disk.id
        Task {
            do { details = try await Task.detached(priority: .userInitiated) { try DiskManagement.details(id) }.value }
            catch { detailError = error.localizedDescription }
        }
    }
    private func run(_ operation: PartitionOperation) {
        close()
        Task { await model.perform(operation, on: disk) }
    }
}

struct DiskBlockedEjectSheet: View {
    let model: DiskManagementModel
    let blocked: BlockedDiskEject
    @State private var confirmForce = false
    private var canQuit: Bool { !model.isPreview && !model.isBusy && blocked.blockers.allSatisfy(\.canQuit) && blocked.disk.protectionReason == nil }

    var body: some View {
        OnePlusSheet("Disk is in use", width: .medium) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("These processes have files open on \(blocked.disk.name). Save your work before closing them.").onePlusText(.row)
                VStack(spacing: 0) {
                    ForEach(blocked.blockers) { blocker in
                        OnePlusKeyValueRow(blocker.name, value: "PID \(blocker.pid)", monospaced: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: "\(blocker.name), PID \(blocker.pid)"))
                    }
                }
                Text(blocked.reason).onePlusText(.caption).textSelection(.enabled)
                if blocked.blockers.contains(where: { !$0.canQuit }) {
                    OnePlusBanner("A protected or other-user process must be closed outside Partition Manager.", tone: .warning)
                }
            }
        } footer: {
            Button("Cancel") { model.blockedEject = nil }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
            Button("Close and Eject") { close(force: false) }.buttonStyle(OnePlusButtonStyle()).disabled(!canQuit)
            Button("Force Quit and Eject", role: .destructive) { confirmForce = true }
                .buttonStyle(OnePlusButtonStyle(.destructive)).disabled(!canQuit)
        }
        .confirmationDialog("Force quit these processes?", isPresented: $confirmForce) {
            Button("Force Quit and Eject", role: .destructive) { close(force: true) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Unsaved work can be lost. Partition Manager checks each process and the disk again before it continues.") }
    }

    private func close(force: Bool) {
        guard canQuit else { return }
        Task { await model.closeBlockersAndEject(blocked, force: force) }
    }
}
