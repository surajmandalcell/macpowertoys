import SwiftUI

@Observable
@MainActor
private final class DiskManagementModel {
    private(set) var disks: [ManagedDisk] = []
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var error: String?

    init(disks: [ManagedDisk] = []) { self.disks = disks }

    func fail(_ error: Error) { self.error = error.localizedDescription }
    func clearError() { error = nil }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            disks = try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func run(_ request: DiskRequest) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        message = nil
        do {
            message = try await Task.detached(priority: .userInitiated) {
                try DiskManagement.run(request)
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
            disks = try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value
        } catch {
            self.error = error.localizedDescription
            if let current = try? await Task.detached(priority: .utility, operation: {
                try DiskManagement.inventory()
            }).value {
                disks = current
            }
        }
        isBusy = false
    }
}

private struct PendingDiskRequest: Identifiable {
    let id = UUID()
    let request: DiskRequest
}

struct DiskModifyView: View {
    private let previewDisks: [ManagedDisk]?
    @State private var model: DiskManagementModel
    @State private var diskID: String?
    @State private var partitionID: String?
    @State private var hoveredPartitionID: String?
    @State private var name = "Untitled"
    @State private var format = "ExFAT"
    @State private var scheme = "GPT"
    @State private var size = "4G"
    @State private var proposedAction: DiskAction?
    @State private var pending: PendingDiskRequest?
    @State private var typedDiskID = ""
    @State private var resizeLimitsText: String?
    @State private var resizeLimitsError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor init(previewDisks: [ManagedDisk]? = nil, previewPartitionID: String? = nil) {
        self.previewDisks = previewDisks
        _model = State(initialValue: DiskManagementModel(disks: previewDisks ?? []))
        _diskID = State(initialValue: previewDisks?.first?.id)
        _partitionID = State(initialValue: previewPartitionID)
    }

    private var disk: ManagedDisk? {
        model.disks.first { $0.id == diskID }
    }
    private var partition: ManagedPartition? {
        disk?.partitions.first { $0.id == partitionID }
    }
    private func unavailableReason(for action: DiskAction, on disk: ManagedDisk) -> String? {
        if model.isBusy { return "Wait for the current operation to finish." }
        if !disk.manageable && action != .verify { return "Only writable removable or external disks can be modified." }
        if action.needsPartition && partition == nil { return "Select a partition or volume above." }
        if action == .addPartition {
            if disk.unallocatedBytes <= 100_000_000 { return "No usable unallocated space. Resize or delete a partition first." }
            if !["GUID_partition_scheme", "FDisk_partition_scheme", "Apple_partition_scheme"].contains(disk.scheme) {
                return "This partition map does not support adding a partition."
            }
        }
        guard let partition else { return nil }
        if [.eraseVolume, .deletePartition, .resizePartition, .mergePartitions].contains(action), partition.isAPFSVolume {
            return "Select its physical APFS container partition."
        }
        if [.rename, .eraseVolume, .deletePartition, .resizePartition, .mergePartitions].contains(action),
            partition.content == "EFI" {
            return "The EFI system partition cannot be changed here."
        }
        if action == .resizePartition && partition.content != "Apple_HFS" {
            return partition.fileSystem == "ExFAT"
                ? "macOS cannot resize ExFAT in place. Back up, erase, and repartition instead."
                : "In-place resize here requires a Journaled HFS+ partition."
        }
        if action == .mergePartitions {
            guard let next = disk.nextPhysicalPartition(after: partition.id), next.content != "EFI",
                  partition.apfsContainer == nil, next.apfsContainer == nil else {
                return "Select a data partition with another data partition immediately after it."
            }
            if partition.content != "Apple_HFS" && partition.fileSystem != "ExFAT" {
                return "Only Journaled HFS+ or ExFAT can be merged here."
            }
        }
        if [.addAPFSVolume, .resizeAPFSContainer].contains(action) &&
            (partition.apfsContainer == nil || partition.isAPFSVolume) {
            return "Select a physical APFS container partition."
        }
        if action == .deleteAPFSVolume && !partition.isAPFSVolume {
            return "Select an APFS volume."
        }
        return nil
    }

    var body: some View {
        WorkspacePage("Modify", subtitle: "Physical disks and partitions", actions: {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .disabled(model.isBusy)
        }) {
            HStack(alignment: .top, spacing: 18) {
                diskList.frame(width: 178)
                VStack(alignment: .leading, spacing: 18) {
                    if let disk {
                        diskSummary(disk)
                        partitionMap(disk)
                        actionWorkspace(disk)
                    } else if model.isBusy && model.disks.isEmpty {
                        ProgressView("Reading physical disks…")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else if model.error != nil {
                        ContentUnavailableView("Couldn’t Read Disks", systemImage: "externaldrive.badge.xmark",
                                               description: Text("Refresh to try again."))
                    } else {
                        ContentUnavailableView(model.disks.isEmpty ? "No Physical Disks" : "Select a Disk",
                                               systemImage: "externaldrive",
                                               description: Text(model.disks.isEmpty ?
                                                   "Connect a disk, then refresh." :
                                                   "Choose a physical disk to inspect its partitions and actions."))
                    }
                    if model.isBusy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Working with disk…")
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("diskman.inventoryError")
                    }
                    if let message = model.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .task { if previewDisks == nil { await model.refresh() } }
        .onChange(of: model.disks.map(\.id)) { _, ids in
            if !ids.contains(diskID ?? "") {
                diskID = model.disks.first(where: \.manageable)?.id ?? model.disks.first?.id
            }
        }
        .onChange(of: diskID) { _, _ in partitionID = nil }
        .sheet(item: $proposedAction, onDismiss: { pending = nil }) { selectedAction in
            if let pending {
                review(pending.request)
            } else if let disk {
                operationForm(selectedAction, on: disk)
            }
        }
    }

    private var diskList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DISKS").utilitySectionHeader().padding(.horizontal, 8)
            ForEach(model.disks) { item in
                Button {
                    withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) { diskID = item.id }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.bus == "Secure Digital" ? "sdcard" : "externaldrive")
                            .font(.system(size: 16))
                            .frame(width: 22)
                            .foregroundStyle(item.manageable ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).lineLimit(1)
                            Text("\(item.id) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 8))
                .background(item.id == disk?.id ? Color.accentColor.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .accessibilityAddTraits(item.id == disk?.id ? .isSelected : [])
                .accessibilityIdentifier("diskman.disk.\(item.id)")
            }
            if model.disks.isEmpty {
                Text(model.isBusy ? "Reading disks…" : "No disks found")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
            }
        }
        .padding(.top, 4)
    }

    private func diskSummary(_ disk: ManagedDisk) -> some View {
        HStack(spacing: 13) {
            Image(systemName: disk.bus == "Secure Digital" ? "sdcard.fill" : "externaldrive.fill")
                .font(.system(size: 24))
                .foregroundStyle(disk.manageable ? Color.accentColor : Color.secondary)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(disk.name).font(.system(size: 17, weight: .semibold))
                Text("/dev/\(disk.id) · \(disk.bus) · \(ByteCountFormatter.string(fromByteCount: disk.size, countStyle: .file))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(disk.manageable ? "WRITABLE" : "INSPECT ONLY")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private func partitionMap(_ disk: ManagedDisk) -> some View {
        let physical = disk.partitions.filter { !$0.isAPFSVolume }
        let unallocated = disk.unallocatedBytes
        let showsFree = unallocated > 100_000_000
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DISK MAP").utilitySectionHeader()
                Spacer()
                Text(disk.scheme.replacingOccurrences(of: "_partition_scheme", with: "") + " · " +
                     "\(physical.count) partition\(physical.count == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(physical.indices, id: \.self) { index in
                        let item = physical[index]
                        let availableWidth = geometry.size.width - CGFloat(physical.count - 1 + (showsFree ? 1 : 0)) * 3
                        let width = max(8, availableWidth * CGFloat(item.size) / CGFloat(max(1, disk.size)))
                        Button {
                            withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) {
                                partitionID = partitionID == item.id ? nil : item.id
                            }
                        } label: {
                            ZStack(alignment: .leading) {
                                DiskMapTexture(color: DiskChartPalette.color(index))
                                if width > 80 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 11)
                                }
                            }
                            .frame(width: width, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(partitionID == item.id ? .white : .clear, lineWidth: 2)
                                .padding(3))
                            .opacity(partitionID == nil || partitionID == item.id || hoveredPartitionID == item.id ? 1 : 0.7)
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveredPartitionID = $0 ? item.id : nil }
                        .help("\(item.name) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                        .accessibilityLabel("\(item.name), /dev/\(item.id), \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                        .accessibilityIdentifier("diskman.map.\(item.id)")
                        .accessibilityAddTraits(partitionID == item.id ? .isSelected : [])
                    }
                    if showsFree {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.045))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            .frame(width: max(8, geometry.size.width * CGFloat(unallocated) /
                                              CGFloat(max(1, disk.size))), height: 72)
                            .help("Unallocated · \(ByteCountFormatter.string(fromByteCount: unallocated, countStyle: .file))")
                    }
                }
            }
            .frame(height: 72)
            Text("Select a segment or row to work on a partition. Disk-wide actions remain available below.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(disk.partitions.indices, id: \.self) { index in
                let item = disk.partitions[index]
                Button {
                    withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) {
                        partitionID = partitionID == item.id ? nil : item.id
                    }
                } label: {
                    HStack(spacing: 9) {
                        Circle().fill(DiskChartPalette.color(index)).frame(width: 8, height: 8)
                            .padding(.leading, item.isAPFSVolume ? 16 : 0)
                        Text(item.name).lineLimit(1)
                        Text(item.displayType).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(item.id).foregroundStyle(.tertiary).font(.system(size: 10, design: .monospaced))
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 7))
                .background(partitionID == item.id ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .accessibilityAddTraits(partitionID == item.id ? .isSelected : [])
                .accessibilityIdentifier("diskman.partition.\(item.id)")
            }
            if disk.partitions.isEmpty {
                Text("No partitions are visible in macOS.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if showsFree {
                HStack(spacing: 9) {
                    Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
                    Text("Unallocated (approx.)")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: unallocated, countStyle: .file))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
            }
        }
        .padding(13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func actionWorkspace(_ disk: ManagedDisk) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .firstTextBaseline) {
                Text(partition.map { "SELECTED  /dev/\($0.id)  ·  \($0.name)" } ?? "SELECTED  WHOLE DISK")
                    .utilitySectionHeader()
                    .lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(partition.map { "Selected /dev/\($0.id), \($0.name)" } ?? "Selected whole disk")
                    .accessibilityIdentifier("diskman.selectedTarget")
                Spacer(minLength: 4)
                if partition != nil {
                    Button("Whole disk") { withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) { partitionID = nil } }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .accessibilityIdentifier("diskman.wholeDisk")
                }
            }
            if let partition, let next = disk.nextPhysicalPartition(after: partition.id),
               unavailableReason(for: .mergePartitions, on: disk) == nil {
                Label(partition.fileSystem == "ExFAT"
                      ? "Merge with \(next.name) erases both volumes. macOS cannot resize ExFAT in place."
                      : "Merge with \(next.name) keeps this Journaled HFS+ volume and erases \(next.name).",
                      systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if partition?.fileSystem == "ExFAT" {
                Label("macOS cannot resize ExFAT in place.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            actionGroup("PARTITION & CAPACITY", actions: [.addPartition, .resizePartition, .mergePartitions,
                                                           .deletePartition, .partitionDisk, .resizeAPFSContainer], disk: disk)
            actionGroup("VOLUMES & FORMATS", actions: [.rename, .eraseVolume, .addAPFSVolume,
                                                       .deleteAPFSVolume, .eraseDisk], disk: disk)
            actionGroup("HEALTH & DEVICE", actions: [.verify, .repair, .mount, .unmount,
                                                      .eject, .wipeDisk], disk: disk)
        }
    }

    private func actionGroup(_ title: String, actions: [DiskAction], disk: ManagedDisk) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).utilitySectionHeader()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 250), spacing: 8)], spacing: 8) {
                ForEach(actions) { action in actionTile(action, disk: disk) }
            }
        }
    }

    private func actionTile(_ action: DiskAction, disk: ManagedDisk) -> some View {
        let reason = unavailableReason(for: action, on: disk)
        return Button {
            model.clearError()
            resizeLimitsText = nil
            resizeLimitsError = nil
            name = action.needsWholeDisk ? "Untitled" : partition?.name ?? "Untitled"
            if action != .rename && action != .mergePartitions && name.count > 11 { name = "Untitled" }
            if action == .addAPFSVolume { format = "APFS" }
            if action == .resizePartition || action == .resizeAPFSContainer { size = "R" }
            pending = nil
            proposedAction = action
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: actionSymbol(action))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(reason == nil ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(action.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(reason == nil ? Color.primary : Color.secondary)
                        Spacer(minLength: 0)
                        if action.needsWholeDisk {
                            Text("DISK")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(reason ?? actionHint(action))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 51, alignment: .topLeading)
            .padding(9)
            .background(Color.primary.opacity(reason == nil ? 0.045 : 0.018),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(reason == nil ? 0.07 : 0.035), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 8))
        .disabled(reason != nil)
        .help(reason ?? actionHint(action))
        .accessibilityLabel(action.rawValue)
        .accessibilityHint(reason ?? actionHint(action))
        .accessibilityIdentifier("diskman.action.\(action.id)")
    }

    private func actionSymbol(_ action: DiskAction) -> String {
        switch action {
        case .verify: "checkmark.shield"
        case .repair: "cross.case"
        case .mount: "arrow.up.to.line"
        case .unmount: "arrow.down.to.line"
        case .eject: "eject"
        case .rename: "pencil"
        case .eraseVolume, .eraseDisk: "eraser"
        case .partitionDisk, .addPartition: "rectangle.split.2x1"
        case .deletePartition, .deleteAPFSVolume: "minus.square"
        case .resizePartition, .resizeAPFSContainer: "arrow.left.and.right"
        case .mergePartitions: "square.on.square"
        case .addAPFSVolume: "plus.square"
        case .wipeDisk: "square.dashed"
        }
    }

    private func actionHint(_ action: DiskAction) -> String {
        switch action {
        case .verify: "Check the selected disk or volume"
        case .repair: "Repair file-system errors"
        case .mount: "Make this volume available"
        case .unmount: "Safely close this volume"
        case .eject: "Disconnect the entire disk"
        case .rename: "Change the volume name"
        case .eraseVolume: "Format this volume"
        case .eraseDisk: "Erase and reformat everything"
        case .partitionDisk: "Replace layout with two partitions"
        case .addPartition: "Use unallocated space"
        case .deletePartition: "Turn partition into free space"
        case .resizePartition: "Resize Journaled HFS+ in place"
        case .mergePartitions: partition?.fileSystem == "ExFAT"
            ? "Erase both and combine" : "Keep first; erase next"
        case .addAPFSVolume: "Share an APFS container"
        case .deleteAPFSVolume: "Remove an APFS volume"
        case .resizeAPFSContainer: "Change APFS container size"
        case .wipeDisk: "Overwrite all sectors with zeros"
        }
    }

    private func operationForm(_ action: DiskAction, on disk: ManagedDisk) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(action.rawValue).font(.system(size: 18, weight: .semibold))
            Text("\(action.needsWholeDisk ? disk.name : partition?.name ?? disk.name) · /dev/\(action.needsWholeDisk ? disk.id : partition?.id ?? disk.id)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            if [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition,
                .mergePartitions, .addAPFSVolume].contains(action) {
                TextField("Volume name", text: $name).textFieldStyle(.roundedBorder)
            }
            if [.eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .addAPFSVolume].contains(action) {
                Picker("Format", selection: $format) {
                    ForEach(action == .addAPFSVolume ? ["APFS", "APFSX"] :
                            ["APFS", "APFSX", "JHFS+", "JHFSX", "HFS+", "HFSX",
                             "ExFAT", "MS-DOS", "MS-DOS FAT12", "MS-DOS FAT16", "FAT32"], id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
            }
            if [.eraseDisk, .partitionDisk].contains(action) {
                Picker("Partition map", selection: $scheme) {
                    Text("GUID (GPT)").tag("GPT")
                    Text("Master Boot Record (MBR)").tag("MBR")
                    Text("Apple Partition Map (APM)").tag("APM")
                }
            }
            if [.partitionDisk, .addPartition, .resizePartition, .resizeAPFSContainer].contains(action) {
                TextField(action == .partitionDisk ? "First partition size, for example 4G" :
                          "Size, for example 4G or R for all available space", text: $size)
                    .textFieldStyle(.roundedBorder)
            }
            if [.resizePartition, .resizeAPFSContainer].contains(action) ||
                action == .mergePartitions && partition?.content == "Apple_HFS" {
                if let resizeLimitsText {
                    Text(action == .mergePartitions ? "macOS confirms the first partition can grow without erasing it.\n" +
                         resizeLimitsText : resizeLimitsText)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                } else if let resizeLimitsError {
                    Label(resizeLimitsError, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    ProgressView("Checking macOS resize limits…").controlSize(.small)
                }
            }
            if action == .mergePartitions, let partition,
               let next = disk.nextPhysicalPartition(after: partition.id) {
                Label("/dev/\(partition.id) + /dev/\(next.id). " +
                      (partition.fileSystem == "ExFAT" ? "Both partitions will be erased." :
                       "The first partition is preserved; the next is erased."),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.system(size: 11))
            } else if action.destroysData {
                Label("This action can permanently remove data. Keep a backup.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.system(size: 11))
            }
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { proposedAction = nil }
                Button("Review…") {
                    let request = DiskRequest(disk: disk,
                                              partition: action.needsWholeDisk ? nil : partition,
                                              action: action, name: name, format: format, scheme: scheme, size: size)
                    do {
                        _ = try request.arguments()
                        model.clearError()
                        typedDiskID = ""
                        pending = PendingDiskRequest(request: request)
                    } catch { model.fail(error) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("diskman.reviewAction")
                .disabled(([.resizePartition, .resizeAPFSContainer].contains(action) ||
                           action == .mergePartitions && partition?.content == "Apple_HFS") &&
                          resizeLimitsText == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task(id: action) {
            guard let partition,
                  [.resizePartition, .resizeAPFSContainer, .mergePartitions].contains(action),
                  action != .mergePartitions || partition.content == "Apple_HFS" else { return }
            do {
                let output = try await Task.detached(priority: .utility) {
                    try DiskManagement.resizeLimits(for: partition.id, apfs: action == .resizeAPFSContainer)
                }.value
                let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("Current") || $0.hasPrefix("Minimum") || $0.hasPrefix("Maximum") }
                resizeLimitsText = lines.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) :
                    lines.joined(separator: "\n")
            } catch {
                resizeLimitsError = error.localizedDescription
            }
        }
    }

    private func review(_ request: DiskRequest) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Review disk operation").font(.system(size: 17, weight: .semibold))
            Text(request.summary).font(.system(size: 12)).textSelection(.enabled)
            if ![.verify, .repair, .mount, .unmount, .eject, .deletePartition,
                 .deleteAPFSVolume, .wipeDisk].contains(request.action) {
                VStack(alignment: .leading, spacing: 7) {
                    if [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition,
                        .mergePartitions,
                        .addAPFSVolume].contains(request.action) {
                        reviewDetail("Name", request.name)
                    }
                    if [.eraseVolume, .eraseDisk, .partitionDisk, .addPartition,
                        .addAPFSVolume].contains(request.action) {
                        reviewDetail("Format", request.format)
                    }
                    if [.eraseDisk, .partitionDisk].contains(request.action) {
                        reviewDetail("Map", request.scheme)
                    }
                    if [.partitionDisk, .addPartition, .resizePartition,
                        .resizeAPFSContainer].contains(request.action) {
                        reviewDetail("Size", request.size == "R" ? "Fill available space" : request.size)
                    }
                }
                .padding(11)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            Text(request.action.destroysData
                 ? "This changes the disk layout or data. Back up the device first; data loss may be permanent."
                 : "Diskman checks the device identity again immediately before running this action.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if request.action == .mergePartitions,
               let first = request.partition,
               let next = request.disk.nextPhysicalPartition(after: first.id) {
                let consequence = first.fileSystem == "ExFAT"
                    ? "ExFAT merge erases both /dev/\(first.id) and /dev/\(next.id)."
                    : "Journaled HFS+ merge keeps /dev/\(first.id) and erases /dev/\(next.id)."
                Text(consequence)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(consequence)
                    .accessibilityIdentifier("diskman.mergeConsequence")
            }
            if request.action == .wipeDisk {
                Text("Zero-fill removes the partition map. Format the disk afterward before using it again.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if request.action.destroysData {
                TextField("Type \(request.disk.id) to confirm", text: $typedDiskID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("diskman.confirmDevice")
            }
            HStack {
                Spacer()
                Button("Cancel") { pending = nil; proposedAction = nil }
                Button(request.action.rawValue) {
                    pending = nil
                    proposedAction = nil
                    Task {
                        await model.run(request)
                        if !model.disks.flatMap(\.partitions).contains(where: { $0.id == partitionID }) {
                            partitionID = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(request.action.destroysData ? .red : .accentColor)
                .disabled(previewDisks != nil || request.action.destroysData && typedDiskID != request.disk.id)
                .accessibilityIdentifier("diskman.executeAction")
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func reviewDetail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.system(size: 11))
    }
}

private struct DiskMapTexture: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.gradient)
            .overlay {
                Canvas { context, size in
                    for row in stride(from: 0.0, through: size.height, by: 8) {
                        for column in stride(from: 0.0, through: size.width, by: 8) {
                            let offset = Int(row / 8) % 2 == 0 ? 0.0 : 4.0
                            context.fill(Path(ellipseIn: CGRect(x: column + offset, y: row,
                                                                width: 1.5, height: 1.5)),
                                         with: .color(.white.opacity(0.23)))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}
