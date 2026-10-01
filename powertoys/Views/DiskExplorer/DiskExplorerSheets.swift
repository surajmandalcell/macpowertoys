import OnePlusUI
import SwiftUI

struct DiskExplorerReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: DiskExplorerModel
    let includeHidden: Bool
    @State private var confirmPermanent = false
    @State private var confirmTrash = false
    private var count: String { "\(model.markedEntries.count) item\(model.markedEntries.count == 1 ? "" : "s")" }

    var body: some View {
        OnePlusSheet("Review items", width: .large) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("\(count) · \(model.markedBytes.diskSize)").onePlusText(.sectionTitle)
                    .accessibilityIdentifier("diskman.reviewSummary")
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.markedEntries) { entry in
                            HStack(spacing: OnePlusMetrics.actionSpacing) {
                                Image(systemName: DiskEntryPresentation.symbol(entry))
                                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                                    Text(entry.name).onePlusText(.row).lineLimit(1)
                                    Text(entry.url.path).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(entry.allocatedBytes.diskSize).onePlusText(.mono)
                                Button { model.toggleMark(entry) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(OnePlusButtonStyle(.icon)).help("Remove from review").accessibilityLabel("Remove \(entry.name) from review")
                            }.onePlusTableRow()
                        }
                    }
                }.thinScrollIndicators().frame(height: OnePlusDiskmanMetrics.inspectorWidth)
            }
        } footer: {
            Button("Cancel") { dismiss() }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
            Button("Delete Permanently...", role: .destructive) { confirmPermanent = true }
                .buttonStyle(OnePlusButtonStyle(.destructive)).disabled(model.marks.isEmpty || model.isRemoving)
            Button("Move to Trash...") { confirmTrash = true }
                .buttonStyle(OnePlusButtonStyle(.primary)).disabled(model.marks.isEmpty || model.isRemoving)
        }
        .confirmationDialog("Permanently delete \(count)?", isPresented: $confirmPermanent) {
            Button("Delete Permanently", role: .destructive) { remove(permanently: true) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This cannot be undone. \(model.markedBytes.diskSize) is selected.") }
        .confirmationDialog("Move \(count) to Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { remove(permanently: false) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Diskman checks the location and file identities again before removal.") }
    }
    private func remove(permanently: Bool) { model.removeMarked(permanently: permanently, includeHidden: includeHidden); dismiss() }
}

struct DiskBlockedEjectSheet: View {
    let model: DiskManagementModel
    let blocked: BlockedDiskEject
    @State private var confirmForce = false
    private var canQuit: Bool { !model.isPreview && !model.isBusy && blocked.blockers.allSatisfy(\.canQuit) && !model.isLocked(blocked.disk) }
    var body: some View {
        OnePlusSheet("Disk is in use", width: .medium) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("These processes have files open on \(blocked.disk.name). Save your work before closing them.").onePlusText(.row)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(blocked.blockers) { blocker in
                            OnePlusKeyValueRow(blocker.name, value: "PID \(blocker.pid)", monospaced: true)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(verbatim: "\(blocker.name), PID \(blocker.pid)"))
                        }
                    }
                }.thinScrollIndicators().frame(maxHeight: OnePlusMetrics.wideControlColumn)
                Text(blocked.reason).onePlusText(.caption).textSelection(.enabled)
                if blocked.blockers.contains(where: { !$0.canQuit }) {
                    OnePlusBanner("A protected or other-user process must be closed outside Diskman.", tone: .warning)
                }
            }
        } footer: {
            Button("Cancel") { model.blockedEject = nil }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
            Button("Close and Eject") { close(force: false) }.buttonStyle(OnePlusButtonStyle())
                .disabled(!canQuit).accessibilityIdentifier("diskman.quitAndEject")
            Button("Force Quit and Eject", role: .destructive) { confirmForce = true }.buttonStyle(OnePlusButtonStyle(.destructive))
                .disabled(!canQuit).accessibilityIdentifier("diskman.forceQuitAndEject")
        }
        .confirmationDialog("Force quit these processes?", isPresented: $confirmForce) {
            Button("Force Quit and Eject", role: .destructive) { close(force: true) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Unsaved work can be lost. Diskman will recheck each process and the disk before continuing.") }
    }
    private func close(force: Bool) {
        guard canQuit else { return }
        model.blockedEject = nil
        Task { await model.eject(blocked.disk, closing: blocked.blockers, force: force) }
    }
}
