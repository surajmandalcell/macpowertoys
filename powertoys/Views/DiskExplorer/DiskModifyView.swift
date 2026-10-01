import AppKit
import OnePlusUI
import SwiftUI

private struct PendingDiskRequest: Identifiable {
    let id = UUID()
    let request: DiskRequest
}

struct DiskModifyView: View {
    @State private var model: DiskManagementModel
    @State private var name = "Untitled"
    @State private var format = "ExFAT"
    @State private var scheme = "GPT"
    @State private var size = "4G"
    @State private var proposedAction: DiskAction?
    @State private var pending: PendingDiskRequest?
    @State private var typedDiskID = ""
    @State private var resizeLimitsText: String?
    @State private var resizeLimitsError: String?
    @State private var confirmWrite = false
    @State private var usedBytes: [String: Int64] = [:]
    @State private var hoveredPartitionID: String?
    @State private var refreshTask: Task<Void, Never>?

    @MainActor init(model: DiskManagementModel) { _model = State(initialValue: model) }
    @MainActor init(previewDisks: [ManagedDisk]? = nil, previewPartitionID: String? = nil) {
        _model = State(initialValue: DiskManagementModel(disks: previewDisks ?? [], selectedPartitionID: previewPartitionID,
                                                       isPreview: previewDisks != nil))
    }
    private var disk: ManagedDisk? { model.selectedDisk }
    private var partition: ManagedPartition? { disk?.partitions.first { $0.id == model.selectedPartitionID } }

    private func unavailableReason(for action: DiskAction, on disk: ManagedDisk) -> String? {
        if model.isBusy { return "Wait for the current operation to finish." }
        if action != .verify, let reason = disk.protectionReason { return reason }
        if action != .verify && model.isLocked(disk) { return "Unlock this disk to make changes." }
        if !disk.manageable && action != .verify { return "Only writable removable or external disks can be modified." }
        if action.needsPartition && partition == nil { return "Select a partition or volume above." }
        if action.needsWholeDisk && partition != nil { return "Select Whole disk above." }
        if action == .addPartition {
            if disk.unallocatedBytes <= 100_000_000 { return "No usable free space. Resize or delete a partition first." }
            if !["GUID_partition_scheme", "FDisk_partition_scheme", "Apple_partition_scheme"].contains(disk.scheme) {
                return "This partition map does not support adding a partition."
            }
        }
        guard let partition else { return nil }
        if [.eraseVolume, .deletePartition, .resizePartition, .mergePartitions].contains(action), partition.isAPFSVolume {
            return "Select its physical APFS container partition."
        }
        if [.repair, .rename, .eraseVolume, .deletePartition, .resizePartition, .mergePartitions].contains(action), partition.content == "EFI" {
            return "The EFI system partition cannot be changed here."
        }
        if action == .resizePartition && partition.content != "Apple_HFS" {
            return partition.fileSystem == "ExFAT" ? "macOS cannot resize ExFAT in place. Back up, erase, and repartition instead." :
                "In-place resize requires a Journaled HFS+ partition."
        }
        if action == .mergePartitions {
            guard let next = disk.nextPhysicalPartition(after: partition.id), next.content != "EFI",
                  partition.apfsContainer == nil, next.apfsContainer == nil else {
                return "Select a data partition with another data partition immediately after it."
            }
            if partition.content != "Apple_HFS" && partition.fileSystem != "ExFAT" { return "Only Journaled HFS+ or ExFAT can be merged here." }
        }
        if [.addAPFSVolume, .resizeAPFSContainer].contains(action) && (partition.apfsContainer == nil || partition.isAPFSVolume) {
            return "Select a physical APFS container partition."
        }
        if action == .deleteAPFSVolume && !partition.isAPFSVolume { return "Select an APFS volume." }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            OnePlusPage {
                OnePlusPageHeader(title: disk?.name ?? "Devices",
                                  subtitle: disk.map { "\($0.id) · \($0.size.diskSize) · \($0.scheme)" } ?? "Physical disks and partitions",
                                  subtitleRole: .mono) { headerActions }
            } footer: {
                if model.isBusy {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        ProgressView().controlSize(.small)
                        Text(model.progressText).onePlusText(.row)
                        Spacer()
                    }
                }
            } content: {
                if let disk {
                    if model.isPreview { OnePlusBanner("Preview data. Disk operations are disabled.") }
                    if let reason = disk.protectionReason {
                        OnePlusBanner(reason, tone: .warning).accessibilityIdentifier("diskman.protectedDisk")
                    }
                    partitionMap(disk)
                    partitions(disk)
                    actions(disk)
                    stagedReview.id("review")
                } else if model.error == nil {
                    OnePlusCard {
                        OnePlusEmptyState(model.isBusy ? "Reading physical disks..." : "No physical disk selected", systemImage: "externaldrive",
                                          caption: "Connect a disk, then refresh.") { Button("Refresh", action: refresh).disabled(model.isBusy) }
                    }
                }
                if let error = model.error { OnePlusBanner(error, tone: .error).accessibilityIdentifier("diskman.inventoryError") }
                if let message = model.message, !message.isEmpty {
                    OnePlusCard { Text(message).onePlusText(.mono).textSelection(.enabled).padding(OnePlusMetrics.cardPadding) }
                }
            }
            .onChange(of: pending?.id) { _, id in if id != nil { proxy.scrollTo("review", anchor: .bottom) } }
        }
        .sheet(item: $proposedAction) { action in if let disk { operationForm(action, on: disk) } }
        .confirmationDialog("Apply the reviewed disk operation?", isPresented: $confirmWrite) {
            if let pending {
                Button(pending.request.action.rawValue, role: .destructive) { execute(pending.request) }
                    .disabled(!canExecute(pending.request))
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text((pending?.request.summary ?? "") + "\nDisk data or layout will change. Keep a backup before continuing.") }
        .onChange(of: model.selectedDiskID) { _, _ in pending = nil; typedDiskID = "" }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
        .task(id: disk?.identity) { await readUsage() }
    }

    private var headerActions: some View {
        OnePlusHeaderActions {
            if let disk {
                Button(model.isLocked(disk) ? "Unlock disk" : "Lock disk", systemImage: model.isLocked(disk) ? "lock.fill" : "lock.open") {
                    model.setLocked(!model.isLocked(disk), for: disk)
                }.buttonStyle(OnePlusButtonStyle()).disabled(model.isBusy || model.isPreview || !disk.manageable)
                    .accessibilityIdentifier("diskman.lockDisk")
                Button("Eject", systemImage: "eject") { Task { await model.eject(disk) } }
                    .buttonStyle(OnePlusButtonStyle()).disabled(model.isBusy || model.isPreview || model.isLocked(disk) || !disk.manageable)
            }
            Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(OnePlusButtonStyle(.icon)).disabled(model.isBusy || model.isPreview)
                .help("Refresh devices").accessibilityLabel("Refresh devices")
        }
    }
    private func refresh() { refreshTask?.cancel(); refreshTask = Task { await model.refresh() } }

    private func partitionMap(_ disk: ManagedDisk) -> some View {
        let physical = disk.partitions.filter { !$0.isAPFSVolume }
        return OnePlusCard {
            OnePlusCardHeader("Partition map", systemImage: "internaldrive") {
                Button("Whole disk") { model.selectedPartitionID = nil }
                    .buttonStyle(OnePlusButtonStyle(model.selectedPartitionID == nil ? .neutral : .ghost, size: .small))
                    .accessibilityIdentifier("diskman.wholeDisk")
                    .accessibilityAddTraits(model.selectedPartitionID == nil ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                GeometryReader { geometry in
                    if DiskChartGeometry.isDrawable(CGRect(origin: .zero, size: geometry.size)) {
                        HStack(spacing: OnePlusMetrics.spacing[0]) {
                            ForEach(physical.indices, id: \.self) { index in
                                let item = physical[index]
                                let width = DiskChartGeometry.partitionWidth(bytes: item.size, total: disk.size,
                                    available: geometry.size.width - CGFloat(physical.count) * OnePlusMetrics.spacing[0])
                                if width > 0 {
                                    Button { model.selectedPartitionID = item.id } label: {
                                        OnePlusStorageTile(color: DiskChartPalette.color(index), selected: model.selectedPartitionID == item.id,
                                                           hovered: hoveredPartitionID == item.id, partition: true) {
                                            if width > OnePlusDiskmanMetrics.tileLabelWidth {
                                                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
                                                    Text(item.name).font(.system(size: OnePlusTextRole.cardTitle.size(for: .regular), weight: .semibold))
                                                    Text(item.size.diskSize).font(.system(size: OnePlusTextRole.mono.size(for: .regular), design: .monospaced))
                                                }.foregroundStyle(OnePlusStorageStyle.ink).lineLimit(1)
                                            }
                                        }
                                    }.buttonStyle(.plain).frame(width: width)
                                        .onHover { hoveredPartitionID = $0 ? item.id : nil }
                                        .help("\(item.name) · \(item.size.diskSize)").accessibilityLabel("\(item.name), \(item.size.diskSize)")
                                        .accessibilityIdentifier("diskman.map.\(item.id)")
                                        .accessibilityAddTraits(model.selectedPartitionID == item.id ? .isSelected : [])
                                        .contextMenu { Button("Select partition") { model.selectedPartitionID = item.id } }
                                }
                            }
                            if disk.unallocatedBytes > 0 {
                                OnePlusColor.track.frame(maxWidth: .infinity).help("Unallocated: \(disk.unallocatedBytes.diskSize)")
                            }
                        }
                    }
                }.frame(height: OnePlusDiskmanMetrics.partitionHeight)
                HStack(spacing: OnePlusMetrics.cardGap) {
                    ForEach(physical.indices, id: \.self) { index in
                        Label { Text(physical[index].name).lineLimit(1) } icon: {
                            Circle().fill(DiskChartPalette.color(index)).frame(width: OnePlusMetrics.actionSpacing, height: OnePlusMetrics.actionSpacing)
                        }.onePlusText(.caption)
                    }
                    Spacer()
                    Text("\(disk.unallocatedBytes.diskSize) unallocated").onePlusText(.caption)
                }
            }.padding(OnePlusMetrics.cardPadding)
        }
    }

    private func partitions(_ disk: ManagedDisk) -> some View {
        OnePlusCard {
            OnePlusCardHeader("Partitions", systemImage: "rectangle.split.2x1") {
                Text(model.isLocked(disk) ? "Write locked" : disk.manageable ? "Writable" : "Inspect only").onePlusText(.caption)
            }
            partitionCells(name: "Name", format: "Format", size: "Size", used: "Used", mount: "Mount point", protection: "Protection")
                .onePlusTableHeader()
            ForEach(Array(zip(disk.partitions.indices, disk.partitions)), id: \.1.id) { index, item in
                Button { model.selectedPartitionID = item.id } label: {
                    partitionCells(name: item.name, format: item.displayType, size: item.size.diskSize,
                                   used: usedBytes[item.id]?.diskSize ?? "-", mount: item.mountPoint ?? "Not mounted",
                                   protection: item.content == "EFI" ? "ESP · Protected" : "-", child: item.isAPFSVolume)
                        .onePlusTableRow(index: index, selected: model.selectedPartitionID == item.id)
                }.buttonStyle(OnePlusInteractionStyle(selected: model.selectedPartitionID == item.id))
                    .accessibilityIdentifier("diskman.partition.\(item.id)")
                    .accessibilityAddTraits(model.selectedPartitionID == item.id ? .isSelected : [])
                    .accessibilityLabel("\(item.name), \(item.displayType), \(item.content == "EFI" ? "EFI system partition, protected" : item.id)")
                    .contextMenu {
                        Button("Select partition") { model.selectedPartitionID = item.id }
                        if let mount = item.mountPoint { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: mount)]) } }
                    }
            }
            if disk.partitions.isEmpty { OnePlusEmptyState("No partitions", systemImage: "internaldrive") }
        }
    }
    private func partitionCells(name: String, format: String, size: String, used: String, mount: String, protection: String, child: Bool = false) -> some View {
        HStack(spacing: OnePlusMetrics.cardGap) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                if child { Image(systemName: "arrow.turn.down.right").foregroundStyle(OnePlusColor.muted).accessibilityHidden(true) }
                Text(name)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(format).frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
            Text(size).frame(width: OnePlusMetrics.controlColumn / 2, alignment: .trailing)
            Text(used).frame(width: OnePlusMetrics.controlColumn / 2, alignment: .trailing)
            Text(mount).frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
            Text(protection).frame(width: OnePlusMetrics.controlColumn, alignment: .leading)
        }.lineLimit(1).truncationMode(.middle)
    }

    private func actions(_ disk: ManagedDisk) -> some View {
        let target = partition.map { "Selected \($0.name) · /dev/\($0.id)" } ?? "Selected whole disk"
        return VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            Text(target).onePlusText(.sectionTitle).accessibilityElement(children: .ignore)
                .accessibilityLabel(target).accessibilityIdentifier("diskman.selectedTarget")
            if partition?.content == "EFI" {
                OnePlusBanner("EFI is a protected system partition. Diskman cannot delete or resize it.", tone: .warning)
                    .accessibilityIdentifier("diskman.protectedEFI")
            }
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                actionGroup("Partition and capacity", [.resizePartition, .addPartition, .deletePartition, .mergePartitions, .partitionDisk, .resizeAPFSContainer], disk)
                actionGroup("Volumes and formats", [.rename, .eraseVolume, .addAPFSVolume, .deleteAPFSVolume, .eraseDisk], disk)
                actionGroup("Health and device", [.verify, .repair, .mount, .unmount, .eject, .wipeDisk], disk)
            }
        }
    }
    private func actionGroup(_ title: String, _ actions: [DiskAction], _ disk: ManagedDisk) -> some View {
        OnePlusCard {
            OnePlusCardHeader(title)
            ForEach(actions) { action in
                let reason = unavailableReason(for: action, on: disk)
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
                    Button(action.rawValue, systemImage: actionSymbol(action)) { propose(action) }
                        .buttonStyle(OnePlusButtonStyle(action.destroysData ? .destructive : .neutral))
                        .disabled(reason != nil).help(reason ?? actionHint(action))
                        .accessibilityHint(reason ?? actionHint(action))
                        .accessibilityIdentifier("diskman.action.\(action.id)")
                    Text(reason ?? actionHint(action)).onePlusText(.caption).lineLimit(2).help(reason ?? actionHint(action))
                }.padding(.horizontal, OnePlusMetrics.cardPadding).padding(.vertical, OnePlusMetrics.actionSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func propose(_ action: DiskAction) {
        model.clearError(); resizeLimitsText = nil; resizeLimitsError = nil
        name = action.needsWholeDisk ? "Untitled" : partition?.name ?? "Untitled"
        if action != .rename && action != .mergePartitions && name.count > 11 { name = "Untitled" }
        if action == .addAPFSVolume { format = "APFS" }
        if action == .resizePartition || action == .resizeAPFSContainer { size = "R" }
        proposedAction = action
    }
    private func actionSymbol(_ action: DiskAction) -> String {
        switch action {
        case .verify: "checkmark.shield"; case .repair: "cross.case"; case .mount: "arrow.up.to.line"
        case .unmount: "arrow.down.to.line"; case .eject: "eject"; case .rename: "pencil"
        case .eraseVolume, .eraseDisk: "eraser"; case .partitionDisk, .addPartition: "rectangle.split.2x1"
        case .deletePartition, .deleteAPFSVolume: "minus.square"; case .resizePartition, .resizeAPFSContainer: "arrow.left.and.right"
        case .mergePartitions: "square.on.square"; case .addAPFSVolume: "plus.square"; case .wipeDisk: "square.dashed"
        }
    }
    private func actionHint(_ action: DiskAction) -> String {
        switch action {
        case .verify: "Check the selected disk or volume"; case .repair: "Repair file-system errors"
        case .mount: "Make this volume available"; case .unmount: "Safely close this volume"
        case .eject: "Disconnect the entire disk"; case .rename: "Change the volume name"
        case .eraseVolume: "Format this volume"; case .eraseDisk: "Erase and reformat everything"
        case .partitionDisk: "Replace layout with two partitions"; case .addPartition: "Use unallocated space"
        case .deletePartition: "Turn partition into free space"; case .resizePartition: "Resize Journaled HFS+ in place"
        case .mergePartitions: partition?.fileSystem == "ExFAT" ? "Erase both and combine" : "Keep first; erase next"
        case .addAPFSVolume: "Share an APFS container"; case .deleteAPFSVolume: "Remove an APFS volume"
        case .resizeAPFSContainer: "Change APFS container size"; case .wipeDisk: "Overwrite all sectors with zeros"
        }
    }

    private func needsLimits(_ action: DiskAction) -> Bool {
        [.resizePartition, .resizeAPFSContainer].contains(action) || action == .mergePartitions && partition?.content == "Apple_HFS"
    }
    private func operationForm(_ action: DiskAction, on disk: ManagedDisk) -> some View {
        OnePlusSheet(action.rawValue, width: .medium) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("\(action.needsWholeDisk ? disk.name : partition?.name ?? disk.name) · /dev/\(action.needsWholeDisk ? disk.id : partition?.id ?? disk.id)").onePlusText(.mono)
                formFields(action)
                if needsLimits(action) {
                    if let resizeLimitsText { Text(resizeLimitsText).onePlusText(.mono).textSelection(.enabled) }
                    else if let resizeLimitsError { OnePlusBanner(resizeLimitsError, tone: .error) }
                    else { ProgressView("Checking macOS resize limits...").controlSize(.small) }
                }
                if action == .mergePartitions, let partition, let next = disk.nextPhysicalPartition(after: partition.id) {
                    OnePlusBanner("/dev/\(partition.id) + /dev/\(next.id). " + (partition.fileSystem == "ExFAT" ? "Both partitions will be erased." :
                        "The first partition is preserved; the next is erased."), tone: .warning)
                } else if action.destroysData { OnePlusBanner("This action can permanently remove data. Keep a backup.", tone: .warning) }
                if let error = model.error { OnePlusBanner(error, tone: .error) }
            }
        } footer: {
            Button("Cancel") { proposedAction = nil }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
            Button("Review...") { stage(action, on: disk) }.buttonStyle(OnePlusButtonStyle(.primary))
                .accessibilityIdentifier("diskman.reviewAction").disabled(needsLimits(action) && resizeLimitsText == nil)
        }
        .task(id: action) {
            guard let partition, needsLimits(action) else { return }
            do {
                let output = try await Task.detached(priority: .utility) {
                    try DiskManagement.resizeLimits(for: partition.id, apfs: action == .resizeAPFSContainer)
                }.value
                guard !Task.isCancelled else { return }
                let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("Current") || $0.hasPrefix("Minimum") || $0.hasPrefix("Maximum") }
                resizeLimitsText = lines.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) : lines.joined(separator: "\n")
            } catch { if !Task.isCancelled { resizeLimitsError = error.localizedDescription } }
        }
    }
    @ViewBuilder private func formFields(_ action: DiskAction) -> some View {
        if [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .mergePartitions, .addAPFSVolume].contains(action) {
            Text("Volume name").onePlusText(.row)
            OnePlusTextField("Volume name", text: $name)
        }
        if [.eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .addAPFSVolume].contains(action) {
            OnePlusSettingRow("Format") {
                OnePlusSelect(choices: (action == .addAPFSVolume ? ["APFS", "APFSX"] :
                    ["APFS", "APFSX", "JHFS+", "JHFSX", "HFS+", "HFSX", "ExFAT", "MS-DOS", "MS-DOS FAT12", "MS-DOS FAT16", "FAT32"]).map { ($0, $0) },
                              selection: $format, accessibilityLabel: "Format")
            }
        }
        if [.eraseDisk, .partitionDisk].contains(action) {
            OnePlusSettingRow("Partition map") {
                OnePlusSelect(choices: [("GPT", "GUID (GPT)"), ("MBR", "Master Boot Record"), ("APM", "Apple Partition Map")], selection: $scheme, accessibilityLabel: "Partition map")
            }
        }
        if [.partitionDisk, .addPartition, .resizePartition, .resizeAPFSContainer].contains(action) {
            Text(action == .partitionDisk ? "First partition size" : "Size").onePlusText(.row)
            OnePlusTextField("For example, 4G or R for all available space", text: $size)
        }
    }
    private func stage(_ action: DiskAction, on disk: ManagedDisk) {
        let request = DiskRequest(disk: disk, partition: action.needsWholeDisk ? nil : partition,
                                  action: action, name: name, format: format, scheme: scheme, size: size)
        do {
            _ = try request.arguments(); model.clearError(); typedDiskID = ""
            pending = PendingDiskRequest(request: request); proposedAction = nil
        } catch { model.fail(error) }
    }
    private var stagedReview: some View {
        OnePlusCard {
            OnePlusCardHeader("Staged review", systemImage: "list.clipboard") {
                Text(pending == nil ? "No pending operations" : "1 pending operation").onePlusText(.caption)
            }
            if let pending {
                review(pending.request)
            } else {
                Text("Choose an action to review its effect before it runs.").onePlusText(.caption).padding(OnePlusMetrics.cardPadding)
            }
        }
    }
    private func review(_ request: DiskRequest) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            Text(request.summary).onePlusText(.row).textSelection(.enabled)
            HStack(spacing: OnePlusMetrics.cardGap) {
                if [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .mergePartitions, .addAPFSVolume].contains(request.action) {
                    OnePlusKeyValueRow("Name", value: request.name)
                }
                if [.eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .addAPFSVolume].contains(request.action) {
                    OnePlusKeyValueRow("Format", value: request.format)
                }
                if [.partitionDisk, .addPartition, .resizePartition, .resizeAPFSContainer].contains(request.action) {
                    OnePlusKeyValueRow("Size", value: request.size == "R" ? "Fill available space" : request.size)
                }
                if [.eraseDisk, .partitionDisk].contains(request.action) { OnePlusKeyValueRow("Map", value: request.scheme) }
            }
            if request.action == .partitionDisk {
                OnePlusKeyValueRow("Second partition", value: "\(request.name.trimmingCharacters(in: .whitespacesAndNewlines)) 2 · \(request.format) · Remaining space")
                OnePlusBanner("All existing partitions and their data will be erased.", tone: .warning)
            }
            if request.action == .mergePartitions, let first = request.partition, let next = request.disk.nextPhysicalPartition(after: first.id) {
                let consequence = first.fileSystem == "ExFAT" ? "ExFAT merge erases both /dev/\(first.id) and /dev/\(next.id)." :
                    "Journaled HFS+ merge keeps /dev/\(first.id) and erases /dev/\(next.id)."
                Text(consequence).onePlusText(.row).foregroundStyle(OnePlusColor.warn)
                    .accessibilityElement(children: .ignore).accessibilityLabel(consequence)
                    .accessibilityIdentifier("diskman.mergeConsequence")
            }
            if request.action == .wipeDisk { OnePlusBanner("Zero-fill removes the partition map. Format the disk afterward before using it again.", tone: .warning) }
            if request.action.destroysData {
                Text("This changes disk data or layout. Type \(request.disk.id) to confirm the reviewed device.").onePlusText(.row)
                OnePlusTextField("Type \(request.disk.id) to confirm", text: $typedDiskID).accessibilityIdentifier("diskman.confirmDevice")
                    .frame(width: OnePlusDiskmanMetrics.inspectorWidth)
            }
            HStack {
                Text("Diskman checks the device identity again before execution.").onePlusText(.caption)
                Spacer()
                Button("Discard") { self.pending = nil }.buttonStyle(OnePlusButtonStyle(.ghost))
                Button(request.action.rawValue) {
                    if request.action.destroysData { confirmWrite = true } else { execute(request) }
                }.buttonStyle(OnePlusButtonStyle(request.action.destroysData ? .destructive : .primary))
                    .disabled(!canExecute(request)).accessibilityIdentifier("diskman.executeAction")
            }
        }.padding(OnePlusMetrics.cardPadding)
    }
    private func canExecute(_ request: DiskRequest) -> Bool {
        !model.isPreview && !model.isBusy && (!request.action.destroysData || typedDiskID == request.disk.id) &&
        (request.action == .verify || request.disk.manageable && !model.isLocked(request.disk)) &&
        model.disks.contains { $0.identity == request.disk.identity && (request.action == .verify || $0.manageable) }
    }
    private func execute(_ request: DiskRequest) {
        guard canExecute(request) else { return }
        pending = nil
        Task { if request.action == .eject { await model.eject(request.disk) } else { await model.run(request) } }
    }
    private func readUsage() async {
        guard let disk else { usedBytes = [:]; return }
        let values = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: disk.partitions.compactMap { partition -> (String, Int64)? in
                if partition.isAPFSVolume { return (partition.id, partition.size) }
                guard let mount = partition.mountPoint,
                      let values = try? URL(fileURLWithPath: mount).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
                      let capacity = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
                return (partition.id, Int64(max(0, capacity - available)))
            })
        }.value
        if !Task.isCancelled { usedBytes = values }
    }
}
