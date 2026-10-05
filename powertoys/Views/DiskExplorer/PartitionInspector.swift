import OnePlusUI
import SwiftUI

enum PartitionEditor: Equatable {
    case resize(String)
    case create(String)
}

/// The trailing inspector: facts for the selection, then every action grouped by scope.
struct PartitionInspector: View {
    let model: DiskManagementModel
    @Binding var editor: PartitionEditor?
    @Binding var sheet: PartitionSheetRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var disk: ManagedDisk? { model.selectedDisk }
    private var partition: ManagedPartition? {
        switch model.selection {
        case .partition(_, let id)?, .volume(_, let id, _)?: disk?.partitions.first { $0.id == id }
        default: nil
        }
    }
    private var volume: ManagedVolume? {
        guard case .volume(_, _, let id)? = model.selection else { return nil }
        return partition?.volumes.first { $0.id == id }
    }
    private var free: FreeSpace? {
        guard case .free(_, let id)? = model.selection else { return nil }
        return disk?.freeSpaces.first { $0.id == id }
    }

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader(title, systemImage: symbol, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    facts
                    if let partition, partition.isAPFS { volumes(partition) }
                    if let editor, let disk { editorView(editor, disk: disk) }
                    actions
                }.padding(OnePlusMetrics.cardPadding)
            }.onePlusScrollIndicators()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(PartitionMotion.spring(reduceMotion), value: editor)
    }

    private var title: String {
        if let volume { return volume.name }
        if let partition { return partition.displayName }
        if free != nil { return "Unallocated" }
        return disk?.name ?? "No selection"
    }
    private var subtitle: String? {
        if let volume { return "/dev/\(volume.id)" }
        if let partition { return "/dev/\(partition.id)" }
        return disk.map { "/dev/\($0.id)" }
    }
    private var symbol: String {
        if volume != nil || partition != nil { return "rectangle.split.3x1" }
        if free != nil { return "square.dashed" }
        return disk?.symbol ?? "externaldrive"
    }

    @ViewBuilder private var facts: some View {
        VStack(spacing: 0) {
            if let volume {
                OnePlusKeyValueRow("File system", value: "APFS volume")
                OnePlusKeyValueRow("Used", value: volume.usedBytes.diskSize, monospaced: true)
                OnePlusKeyValueRow("Mount point", value: volume.mountPoint ?? "Not mounted", monospaced: true)
            } else if let partition {
                OnePlusKeyValueRow("File system", value: partition.displayFileSystem)
                OnePlusKeyValueRow("Size", value: partition.size.diskSize, monospaced: true)
                OnePlusKeyValueRow("Used", value: partition.usedBytes?.diskSize ?? "Not mounted", monospaced: true)
                OnePlusKeyValueRow("Mount point", value: partition.mountPoint ?? (partition.isMounted ? "See volumes" : "Not mounted"), monospaced: true)
            } else if let free {
                OnePlusKeyValueRow("Size", value: free.size.diskSize, monospaced: true)
                OnePlusKeyValueRow("Starts at", value: free.offset.diskSize, monospaced: true)
            } else if let disk {
                OnePlusKeyValueRow("Partition map", value: disk.schemeTitle)
                OnePlusKeyValueRow("Size", value: disk.size.diskSize, monospaced: true)
                OnePlusKeyValueRow("Connection", value: disk.kind == .image ? "Disk image" : disk.bus)
                OnePlusKeyValueRow("Health", value: disk.smart ?? "Not reported")
            }
            if let reason = disk?.protectionReason {
                Label(reason, systemImage: "lock.fill").onePlusText(.caption).padding(.top, OnePlusMetrics.actionSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("partitions.protected")
            }
        }
    }

    private func volumes(_ partition: ManagedPartition) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
            Text("Volumes").onePlusText(.captionUpper)
            ForEach(partition.volumes) { item in
                let selected = volume?.id == item.id
                Button {
                    withAnimation(PartitionMotion.spring(reduceMotion)) {
                        model.selection = selected ? .partition(disk: disk?.id ?? "", id: partition.id) :
                            .volume(disk: disk?.id ?? "", partition: partition.id, id: item.id)
                    }
                } label: {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Image(systemName: item.mountPoint == nil ? "circle.dashed" : "checkmark.circle.fill").onePlusText(.caption)
                        Text(item.name).onePlusText(.row, selected: selected).lineLimit(1)
                        Spacer(minLength: OnePlusMetrics.actionSpacing)
                        Text(item.usedBytes.diskSize).onePlusText(.mono)
                    }.padding(.horizontal, OnePlusMetrics.actionSpacing).frame(height: OnePlusMetrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OnePlusInteractionStyle(selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("\(item.name), /dev/\(item.id), \(item.mountPoint ?? "not mounted")")
            }
        }
    }

    @ViewBuilder private func editorView(_ editor: PartitionEditor, disk: ManagedDisk) -> some View {
        switch editor {
        case .resize(let id):
            if let partition = disk.partitions.first(where: { $0.id == id }) {
                PartitionResizeEditor(model: model, disk: disk, partition: partition,
                                      cancel: closeEditor, review: { review($0, disk: disk) })
            }
        case .create(let id):
            if let space = disk.freeSpaces.first(where: { $0.id == id }) {
                PartitionCreateEditor(model: model, disk: disk, space: space,
                                      cancel: closeEditor, review: { review($0, disk: disk) })
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            ForEach(PartitionAction.groups, id: \.0) { title, actions in
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[2]) {
                    Text(title).onePlusText(.captionUpper)
                    ForEach(actions.filter(isShown)) { action in actionButton(action) }
                }
            }
        }
    }

    private func isShown(_ action: PartitionAction) -> Bool {
        switch action {
        case .mount: model.unavailableReason(.mount) == nil || model.unavailableReason(.unmount) != nil
        case .unmount: model.unavailableReason(.unmount) == nil
        default: true
        }
    }

    private func actionButton(_ action: PartitionAction) -> some View {
        let reason = model.unavailableReason(action)
        return HStack {
            Button { perform(action) } label: {
                Label(action.rawValue, systemImage: action.systemImage).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(OnePlusButtonStyle(action.isDestructive ? .destructive : .neutral))
            .disabled(reason != nil)
            .accessibilityHint(reason ?? "")
            .accessibilityIdentifier("partitions.action.\(action.id)")
        }
        .contentShape(Rectangle())
        .help(reason ?? action.rawValue)
    }

    private func perform(_ action: PartitionAction) {
        guard let disk, let selection = model.selection else { return }
        model.clearMessages()
        switch action {
        case .mount, .unmount:
            let target = volume?.id ?? partition.map { $0.apfsContainer ?? $0.id } ?? disk.id
            run(action == .mount ? .mount(target: target) : .unmount(target: target), disk: disk)
        case .eject:
            run(.eject, disk: disk)
        case .resize:
            if let partition { editor = .resize(partition.id) }
        case .create:
            if let free { editor = .create(free.id) }
        case .rename, .format, .delete, .eraseDisk, .firstAid, .info:
            sheet = PartitionSheetRequest(kind: .init(action), disk: disk, selection: selection)
        }
    }

    private func run(_ operation: PartitionOperation, disk: ManagedDisk) {
        Task { await model.perform(operation, on: disk) }
    }
    private func review(_ operation: PartitionOperation, disk: ManagedDisk) {
        guard let selection = model.selection else { return }
        sheet = PartitionSheetRequest(kind: .confirm(operation), disk: disk, selection: selection)
    }
    private func closeEditor() {
        withAnimation(PartitionMotion.spring(reduceMotion)) { editor = nil; model.preview = nil }
    }
}

/// Resize an APFS container or Mac OS Extended partition. The map previews the new size while the slider moves.
struct PartitionResizeEditor: View {
    let model: DiskManagementModel
    let disk: ManagedDisk
    let partition: ManagedPartition
    let cancel: () -> Void
    let review: (PartitionOperation) -> Void
    @State private var size: Double = 0
    @State private var minimum: Int64?
    @State private var failure: String?
    @State private var split = false
    @State private var system = PartitionFileSystem.exfat
    @State private var name = "Untitled"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maximum: Int64 {
        partition.size + (disk.freeSpaces.first { $0.afterPartition == partition.id }?.size ?? 0)
    }
    private var bytes: Int64 { Int64(size / 1_000_000) * 1_000_000 }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            Text("New size").onePlusText(.captionUpper)
            if let minimum, minimum < maximum {
                HStack {
                    Text(bytes.diskSize).onePlusText(.mono, color: OnePlusColor.ink)
                    Spacer()
                    Text("\(minimum.diskSize) to \(maximum.diskSize)").onePlusText(.caption)
                }
                Slider(value: $size, in: Double(minimum)...Double(maximum))
                    .accessibilityLabel("New partition size").accessibilityValue(bytes.diskSize)
                Toggle("Create a partition in the freed space", isOn: $split).toggleStyle(OnePlusCheckboxStyle())
                    .onePlusText(.row).disabled(bytes >= maximum - ManagedDisk.minimumFreeSpace)
                if split {
                    OnePlusSelect(choices: fileSystems, selection: $system, width: nil, accessibilityLabel: "File system")
                    OnePlusTextField("Name", text: $name)
                }
                HStack {
                    Button("Cancel", action: cancel).buttonStyle(OnePlusButtonStyle(.ghost))
                    Spacer()
                    Button("Review...") {
                        review(.resize(target: partition.id, size: bytes,
                                       split: split && bytes < maximum - ManagedDisk.minimumFreeSpace ? PartitionSplit(fileSystem: system, name: name) : nil))
                    }.buttonStyle(OnePlusButtonStyle(.primary)).disabled(bytes == partition.size && !split)
                }
            } else if let failure {
                Text(failure).onePlusText(.caption, color: OnePlusColor.danger)
                Button("Cancel", action: cancel).buttonStyle(OnePlusButtonStyle(.ghost))
            } else if minimum != nil {
                Text("This partition cannot be smaller and has no free space after it.").onePlusText(.caption)
                Button("Cancel", action: cancel).buttonStyle(OnePlusButtonStyle(.ghost))
            } else {
                ProgressView("Reading resize limits...").controlSize(.small)
            }
        }
        .padding(OnePlusMetrics.spacing[5])
        .background(OnePlusColor.raised, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
        .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius).strokeBorder(OnePlusColor.line, lineWidth: 1) }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .task(id: partition.id) {
            size = Double(partition.size)
            let target = partition
            do {
                let value = try await Task.detached(priority: .userInitiated) { try DiskManagement.resizeMinimum(for: target) }.value
                minimum = min(max(value, ManagedDisk.minimumFreeSpace), target.size)
            } catch { failure = error.localizedDescription }
        }
        .onChange(of: size) { _, _ in updatePreview() }
        .onChange(of: split) { _, _ in updatePreview() }
        .onDisappear { model.preview = nil }
    }

    private var fileSystems: [(PartitionFileSystem, String)] {
        PartitionFileSystem.allCases.map { ($0, $0.title) }
    }
    private func updatePreview() {
        guard minimum != nil else { return }
        withAnimation(PartitionMotion.spring(reduceMotion)) {
            model.preview = .resize(partition: partition.id, size: bytes, split: split)
        }
    }
}

/// Create a partition in unallocated space. The map previews the new block while the slider moves.
struct PartitionCreateEditor: View {
    let model: DiskManagementModel
    let disk: ManagedDisk
    let space: FreeSpace
    let cancel: () -> Void
    let review: (PartitionOperation) -> Void
    @State private var size: Double = 0
    @State private var system = PartitionFileSystem.exfat
    @State private var name = "Untitled"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bytes: Int64 { size >= Double(space.size) ? space.size : Int64(size / 1_000_000) * 1_000_000 }
    private var choices: [(PartitionFileSystem, String)] {
        PartitionFileSystem.allCases.filter { $0 != .apfs || disk.scheme == "GUID_partition_scheme" }.map { ($0, $0.title) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            Text("New partition").onePlusText(.captionUpper)
            HStack {
                Text(bytes.diskSize).onePlusText(.mono, color: OnePlusColor.ink)
                Spacer()
                Text("of \(space.size.diskSize)").onePlusText(.caption)
            }
            Slider(value: $size, in: Double(ManagedDisk.minimumFreeSpace)...Double(max(space.size, ManagedDisk.minimumFreeSpace + 1)))
                .accessibilityLabel("New partition size").accessibilityValue(bytes.diskSize)
            OnePlusSelect(choices: choices, selection: $system, width: nil, accessibilityLabel: "File system")
            OnePlusTextField("Name", text: $name)
            HStack {
                Button("Cancel", action: cancel).buttonStyle(OnePlusButtonStyle(.ghost))
                Spacer()
                Button("Review...") {
                    review(.create(after: space.afterPartition, fileSystem: system, name: name, size: bytes >= space.size ? nil : bytes))
                }.buttonStyle(OnePlusButtonStyle(.primary))
            }
        }
        .padding(OnePlusMetrics.spacing[5])
        .background(OnePlusColor.raised, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
        .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius).strokeBorder(OnePlusColor.line, lineWidth: 1) }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .onAppear { size = Double(space.size); updatePreview() }
        .onChange(of: size) { _, _ in updatePreview() }
        .onDisappear { model.preview = nil }
    }

    private func updatePreview() {
        withAnimation(PartitionMotion.spring(reduceMotion)) { model.preview = .create(free: space.id, size: bytes) }
    }
}
