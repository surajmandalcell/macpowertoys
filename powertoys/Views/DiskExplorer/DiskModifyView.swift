import SwiftUI

@Observable
@MainActor
private final class DiskManagementModel {
    private(set) var disks: [ManagedDisk] = []
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var error: String?

    func fail(_ error: Error) { self.error = error.localizedDescription }

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
        do {
            message = try await Task.detached(priority: .userInitiated) {
                try DiskManagement.run(request)
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
            disks = try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value
        } catch {
            self.error = error.localizedDescription
        }
        isBusy = false
    }
}

private struct PendingDiskRequest: Identifiable {
    let id = UUID()
    let request: DiskRequest
}

struct DiskModifyView: View {
    @State private var model = DiskManagementModel()
    @State private var diskID: String?
    @State private var partitionID: String?
    @State private var action = DiskAction.verify
    @State private var name = "Untitled"
    @State private var format = "ExFAT"
    @State private var scheme = "GPT"
    @State private var size = "4G"
    @State private var pending: PendingDiskRequest?
    @State private var typedDiskID = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var disk: ManagedDisk? {
        model.disks.first { $0.id == diskID }
    }
    private var partition: ManagedPartition? {
        disk?.partitions.first { $0.id == partitionID }
    }
    private var availableActions: [DiskAction] {
        DiskAction.allCases.filter { action in
            if partition == nil { return !action.needsPartition }
            if action.needsWholeDisk { return false }
            if action == .deleteAPFSVolume { return partition?.isAPFSVolume == true }
            if [.addAPFSVolume, .resizeAPFSContainer].contains(action) {
                return partition?.apfsContainer != nil && partition?.isAPFSVolume == false
            }
            if partition?.isAPFSVolume == true {
                return ![.eraseVolume, .deletePartition, .resizePartition].contains(action)
            }
            if action == .resizePartition { return partition?.content == "Apple_HFS" }
            return true
        }.filter {
            $0 != .addPartition || disk.map {
                $0.unallocatedBytes > 100_000_000 &&
                    ["GUID_partition_scheme", "FDisk_partition_scheme", "Apple_partition_scheme"].contains($0.scheme)
            } == true
        }
    }

    var body: some View {
        WorkspacePage("Modify", subtitle: "Physical disks and partitions", actions: {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .disabled(model.isBusy)
        }) {
            HStack(alignment: .top, spacing: 16) {
                diskList.frame(width: 230)
                VStack(alignment: .leading, spacing: 16) {
                    if let disk {
                        diskSummary(disk)
                        partitionMap(disk)
                        operationCard(disk)
                    } else if model.isBusy && model.disks.isEmpty {
                        ProgressView("Reading physical disks…")
                            .frame(maxWidth: .infinity, minHeight: 260)
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
        .task { await model.refresh() }
        .onChange(of: diskID) { _, _ in partitionID = nil; action = .verify }
        .onChange(of: partitionID) { _, _ in action = .verify }
        .onChange(of: action) { _, newValue in
            if newValue == .addAPFSVolume { format = "APFS" }
        }
        .sheet(item: $pending) { item in
            review(item.request)
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
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func diskSummary(_ disk: ManagedDisk) -> some View {
        HStack(spacing: 13) {
            Image(systemName: disk.bus == "Secure Digital" ? "sdcard.fill" : "externaldrive.fill")
                .font(.system(size: 26))
                .foregroundStyle(disk.manageable ? Color.accentColor : Color.secondary)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(disk.name).font(.system(size: 15, weight: .semibold))
                Text("/dev/\(disk.id) · \(disk.bus) · \(disk.scheme) · \(ByteCountFormatter.string(fromByteCount: disk.size, countStyle: .file))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(disk.manageable ? "READY TO MODIFY" : "READ ONLY HERE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(disk.manageable ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .utilitySectionCard()
    }

    private func partitionMap(_ disk: ManagedDisk) -> some View {
        let physical = disk.partitions.filter { !$0.isAPFSVolume }
        let unallocated = disk.unallocatedBytes
        let showsFree = unallocated > 100_000_000
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PARTITIONS & VOLUMES").utilitySectionHeader()
                Spacer()
                Text("Select a partition to see its actions")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(physical.indices, id: \.self) { index in
                        let item = physical[index]
                        let availableWidth = geometry.size.width - CGFloat(physical.count - 1 + (showsFree ? 1 : 0)) * 3
                        let width = max(3, availableWidth * CGFloat(item.size) / CGFloat(max(1, disk.size)))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DiskChartPalette.color(index).opacity(partitionID == nil || partitionID == item.id ? 1 : 0.5))
                            .frame(width: width)
                            .help("\(item.name) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                    }
                    if showsFree {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: max(3, geometry.size.width * CGFloat(unallocated) /
                                              CGFloat(max(1, disk.size))))
                            .help("Unallocated · \(ByteCountFormatter.string(fromByteCount: unallocated, countStyle: .file))")
                    }
                }
            }
            .frame(height: 14)
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
                        Text(item.content).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                            .monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: partitionID == item.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(partitionID == item.id ? Color.accentColor : Color.secondary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 7))
                .accessibilityAddTraits(partitionID == item.id ? .isSelected : [])
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
        .utilitySectionCard()
    }

    private func operationCard(_ disk: ManagedDisk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OPERATION").utilitySectionHeader()
                Spacer()
                Text(partition.map { "/dev/\($0.id)" } ?? "Whole disk")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Picker("Action", selection: $action) {
                ForEach(availableActions) { value in Text(value.rawValue).tag(value) }
            }
            .pickerStyle(.menu)
            if [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .addAPFSVolume].contains(action) {
                TextField("Volume name", text: $name)
                    .textFieldStyle(.roundedBorder)
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
                TextField(action == .partitionDisk ? "First partition size, for example 4G" : "Size, for example 4G", text: $size)
                    .textFieldStyle(.roundedBorder)
                if action == .partitionDisk {
                    Text("Creates two partitions. The second uses the remaining space.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if action.destroysData {
                Label("This action can permanently remove data. Check the selected device and keep a backup.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Review \(action.rawValue)…") {
                    let request = DiskRequest(disk: disk, partition: partition, action: action,
                                              name: name, format: format, scheme: scheme, size: size)
                    do {
                        _ = try request.arguments()
                        typedDiskID = ""
                        pending = PendingDiskRequest(request: request)
                    } catch {
                        model.fail(error)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !disk.manageable && action != .verify)
            }
        }
        .utilitySectionCard()
        .utilityAnimation(value: action)
    }

    private func review(_ request: DiskRequest) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Review disk operation").font(.system(size: 17, weight: .semibold))
            Text(request.summary).font(.system(size: 12)).textSelection(.enabled)
            if ![.verify, .repair, .mount, .unmount, .eject, .deletePartition,
                 .deleteAPFSVolume, .wipeDisk].contains(request.action) {
                VStack(alignment: .leading, spacing: 7) {
                    if [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition,
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
                Button("Cancel") { pending = nil }
                Button(request.action.rawValue) {
                    pending = nil
                    Task {
                        await model.run(request)
                        action = .verify
                        if !model.disks.flatMap(\.partitions).contains(where: { $0.id == partitionID }) {
                            partitionID = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(request.action.destroysData ? .red : .accentColor)
                .disabled(request.action.destroysData && typedDiskID != request.disk.id)
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
