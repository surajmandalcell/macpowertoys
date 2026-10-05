import OnePlusUI
import SwiftUI

/// One disk: identity header above a proportional partition map.
struct PartitionDiskCard: View {
    let disk: ManagedDisk
    let model: DiskManagementModel
    let namespace: Namespace.ID
    let select: (PartitionSelection) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?

    private var segments: [PartitionMapSegment] {
        PartitionMapLayout.segments(for: disk, preview: model.selection?.diskID == disk.id ? model.preview : nil)
    }

    var body: some View {
        OnePlusCard {
            header
            map.padding(.horizontal, OnePlusMetrics.cardPadding).padding(.bottom, OnePlusMetrics.cardPadding)
        }
    }

    private var header: some View {
        Button { select(.disk(disk.id)) } label: {
            HStack(spacing: OnePlusMetrics.spacing[5]) {
                Image(systemName: disk.symbol).font(.system(size: OnePlusTextRole.sectionTitle.size(for: .regular)))
                    .foregroundStyle(OnePlusColor.secondary).frame(width: OnePlusMetrics.navIcon).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                    Text(disk.name).onePlusText(.sectionTitle).lineLimit(1)
                    Text(disk.summary).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: OnePlusMetrics.actionSpacing)
                if let smart = disk.smart, smart != "Not Supported" {
                    OnePlusStatus("SMART \(smart)", state: smart == "Verified" ? .neutral : .warning)
                }
                if let reason = disk.protectionReason {
                    Label("Protected", systemImage: "lock.fill").labelStyle(.titleAndIcon).onePlusText(.caption)
                        .help(reason).accessibilityLabel("Protected. \(reason)")
                }
            }
            .padding(.horizontal, OnePlusMetrics.cardPadding)
            .frame(height: OnePlusMetrics.captionedSettingRow).contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle())
        .help(disk.imagePath.map { "\(disk.summary)\n\($0)" } ?? disk.summary)
        .accessibilityLabel("\(disk.name), \(disk.summary)")
        .accessibilityAddTraits(model.selection == .disk(disk.id) ? .isSelected : [])
    }

    private var map: some View {
        let items = segments
        return GeometryReader { geometry in
            let widths = PartitionMapLayout.widths(items.map(\.bytes), available: geometry.size.width,
                                                   minimum: PartitionMapMetrics.minimumBlock, spacing: PartitionMapMetrics.blockGap)
            HStack(spacing: PartitionMapMetrics.blockGap) {
                ForEach(Array(zip(items.indices, items)), id: \.1.id) { index, segment in
                    block(segment, colorIndex: colorIndex(of: segment, in: items))
                        .frame(width: widths.indices.contains(index) ? widths[index] : 0)
                        .transition(.asymmetric(insertion: .scale(scale: 0, anchor: .leading).combined(with: .opacity),
                                                removal: .scale(scale: 0, anchor: .leading).combined(with: .opacity)))
                }
                if items.isEmpty {
                    Text("No partition map").onePlusText(.caption).frame(maxWidth: .infinity)
                }
            }
            .overlay { if model.selection == .disk(disk.id) { selectionOutline(radius: OnePlusMetrics.controlRadius) } }
        }
        .frame(height: OnePlusDiskmanMetrics.partitionHeight)
        .animation(PartitionMotion.spring(reduceMotion), value: items)
    }

    private func colorIndex(of segment: PartitionMapSegment, in items: [PartitionMapSegment]) -> Int {
        items.prefix { $0.id != segment.id }.filter { if case .partition = $0.kind { true } else { false } }.count
    }

    @ViewBuilder private func block(_ segment: PartitionMapSegment, colorIndex: Int) -> some View {
        let selected = model.selection?.diskID == disk.id && model.selection?.blockID == segment.id && model.selection != .disk(disk.id)
        let activity = model.activity.flatMap { $0.diskID == disk.id && ($0.blockID == segment.id || $0.blockID == disk.id) ? $0.title : nil }
        Button { select(selection(for: segment)) } label: {
            PartitionBlock(segment: segment, disk: disk, color: OnePlusColor.storageSeries[colorIndex % OnePlusColor.storageSeries.count],
                           hovered: hovered == segment.id, activity: activity)
                .overlay { if selected { selectionOutline(radius: OnePlusDiskmanMetrics.tileRadius) } }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? segment.id : (hovered == segment.id ? nil : hovered) }
        .disabled(segment.id == "pending")
        .help(segment.helpText)
        .accessibilityLabel(segment.helpText)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("partitions.block.\(segment.id)")
    }

    private func selection(for segment: PartitionMapSegment) -> PartitionSelection {
        switch segment.kind {
        case .partition(let partition): .partition(disk: disk.id, id: partition.id)
        case .free(let space): .free(disk: disk.id, id: space.id)
        case .pending: .disk(disk.id)
        }
    }

    private func selectionOutline(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .strokeBorder(OnePlusColor.accent, lineWidth: PartitionMapMetrics.selectionLine)
            .matchedGeometryEffect(id: "partition-selection", in: namespace)
            .allowsHitTesting(false)
    }
}

extension PartitionMapSegment {
    var helpText: String {
        switch kind {
        case .partition(let partition):
            let used = partition.usedBytes.map { ", \($0.diskSize) used" } ?? ""
            let mount = partition.isMounted ? ", mounted" : ", not mounted"
            return "\(partition.displayName), \(partition.displayFileSystem), \(bytes.diskSize)\(used)\(mount), /dev/\(partition.id)"
        case .free: return "Unallocated, \(bytes.diskSize)"
        case .pending(let title): return "\(title), \(bytes.diskSize)"
        }
    }
}

/// One block of the partition map: a partition with its used-space fill, unallocated space, or a previewed partition.
struct PartitionBlock: View {
    let segment: PartitionMapSegment
    let disk: ManagedDisk
    let color: Color
    let hovered: Bool
    let activity: String?
    private let shape = RoundedRectangle(cornerRadius: OnePlusDiskmanMetrics.tileRadius)

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            GeometryReader { geometry in
                if geometry.size.width >= PartitionMapMetrics.labelledBlock { labels } else { compactLabel }
            }.padding(OnePlusMetrics.actionSpacing)
            if let activity { progress(activity) }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(hovered ? OnePlusStorageStyle.hoverLine : OnePlusStorageStyle.line, lineWidth: 1) }
        .contentShape(shape)
    }

    @ViewBuilder private var background: some View {
        switch segment.kind {
        case .partition(let partition):
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    color.overlay(OnePlusColor.desktop.opacity(PartitionMapMetrics.freeSpaceOpacity)).environment(\.colorScheme, .dark)
                    if let used = partition.usedBytes, partition.size > 0 {
                        color.frame(width: geometry.size.width * min(1, max(0, CGFloat(used) / CGFloat(partition.size))))
                    }
                }
            }
        case .free:
            OnePlusColor.track.overlay { PartitionHatch() }
        case .pending:
            OnePlusColor.track.overlay {
                shape.strokeBorder(OnePlusColor.accent, style: StrokeStyle(lineWidth: 1, dash: [OnePlusMetrics.spacing[1], OnePlusMetrics.spacing[1]]))
            }
        }
    }

    @ViewBuilder private var labels: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
            Text(title).onePlusText(.cardTitle, color: ink).lineLimit(1)
            Text(detail).onePlusText(.mono, color: secondaryInk).lineLimit(1)
            Spacer(minLength: 0)
            if case .partition(let partition) = segment.kind {
                HStack(spacing: OnePlusMetrics.spacing[1]) {
                    if disk.protectionReason != nil { Image(systemName: "lock.fill") }
                    Image(systemName: partition.isMounted ? "checkmark.circle.fill" : "circle.dashed")
                    Text(partition.isMounted ? "Mounted" : partition.isEFI ? "System" : "Not mounted").lineLimit(1)
                }.onePlusText(.caption, color: secondaryInk)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compactLabel: some View {
        Text(title).onePlusText(.caption, color: secondaryInk).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func progress(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
            Spacer(minLength: 0)
            Text(title).onePlusText(.caption, color: OnePlusStorageStyle.ink).lineLimit(1)
            ProgressView().progressViewStyle(.linear).controlSize(.small).tint(OnePlusStorageStyle.ink)
        }
        .padding(OnePlusMetrics.actionSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(OnePlusColor.desktop.opacity(PartitionMapMetrics.progressScrimOpacity))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch segment.kind {
        case .partition(let partition): partition.displayName
        case .free: "Unallocated"
        case .pending(let title): title
        }
    }
    private var detail: String {
        switch segment.kind {
        case .partition(let partition): "\(partition.displayFileSystem) · \(segment.bytes.diskSize)"
        case .free, .pending: segment.bytes.diskSize
        }
    }
    private var ink: Color {
        if case .partition = segment.kind { return OnePlusStorageStyle.ink }
        return OnePlusColor.ink
    }
    private var secondaryInk: Color {
        if case .partition = segment.kind { return OnePlusStorageStyle.secondary }
        return OnePlusColor.muted
    }
}

/// Diagonal hatching for unallocated space, drawn once per size.
struct PartitionHatch: View {
    var body: some View {
        Canvas { context, size in
            let step = OnePlusMetrics.actionSpacing
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(OnePlusColor.line), lineWidth: 1)
        }.accessibilityHidden(true)
    }
}
