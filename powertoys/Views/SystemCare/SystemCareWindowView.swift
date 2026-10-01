import AppKit
import OnePlusUI
import QuickLook
import SwiftUI

struct SystemCareByteMetric: Equatable {
    let value: String
    let unit: String

    init(_ bytes: Int64) {
        let parts = bytes.formattedByteCount.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        value = bytes == 0 ? "0" : String(parts.first ?? "0")
        unit = parts.count == 2 ? String(parts[1]) : ""
    }
}

nonisolated struct SystemCareStorageRow: Identifiable, Equatable, Sendable {
    let entry: StorageEntry
    let size: String
    let colorIndex: Int
    var id: String { entry.id }
}

nonisolated struct SystemCareCleanupRow: Identifiable, Equatable, Sendable {
    let candidate: CleanupCandidate
    let size: String
    var id: String { candidate.id }
}

nonisolated struct SystemCareApplicationRow: Identifiable, Equatable, Sendable {
    let application: InstalledApplication
    var size: String?
    var sizeError: String?
    var lastUsed: String?
    var id: String { application.id }
}

nonisolated struct SystemCareApplicationMetadata: Sendable {
    let id: String
    let size: String
    let sizeError: String?
    let lastUsed: String
    let icon: CGImage?
}

private enum SystemCareApplicationLayout {
    static let columns = [
        OnePlusGridColumn("Application", width: OnePlusMetrics.controlColumn * 2,
                          leadingInset: OnePlusTable.primaryIconInset,
                          headerLabelInset: OnePlusMetrics.spacing[7] + OnePlusMetrics.spacing[2]),
        OnePlusGridColumn("Size", width: OnePlusMetrics.controlColumn * 0.75, trailing: true, textRole: .mono),
        OnePlusGridColumn("Last accessed", width: OnePlusMetrics.controlColumn)
    ]
}

private enum SystemCareStorageLayout {
    static let columns = [
        OnePlusGridColumn("Name", width: OnePlusMetrics.controlColumn * 3,
                          leadingInset: OnePlusTable.primaryIconInset,
                          headerLabelInset: OnePlusMetrics.navIcon + OnePlusMetrics.spacing[2]),
        OnePlusGridColumn("Kind", width: OnePlusMetrics.controlColumn),
        OnePlusGridColumn("Size", width: OnePlusMetrics.controlColumn, trailing: true, textRole: .mono)
    ]
}

nonisolated enum SystemCarePresentationRows {
    static func storage(_ entries: [StorageEntry]) -> [SystemCareStorageRow] {
        let formatter = byteFormatter()
        return entries.indices.map { index in
            SystemCareStorageRow(entry: entries[index], size: formatter.string(fromByteCount: entries[index].size), colorIndex: index)
        }
    }

    static func cleanup(_ candidates: [CleanupCandidate]) -> [SystemCareCleanupRow] {
        let formatter = byteFormatter()
        return candidates.map {
            SystemCareCleanupRow(candidate: $0, size: formatter.string(fromByteCount: $0.size))
        }
    }

    static func application(_ application: InstalledApplication) -> SystemCareApplicationMetadata {
        let formatter = byteFormatter()
        let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
        let values = try? application.url.resourceValues(forKeys: [.contentAccessDateKey, .isSymbolicLinkKey])
        let size: String
        let sizeError: String?
        do {
            let rootValues = try application.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard rootValues.isSymbolicLink != true else {
                throw NSError(domain: "SystemCare", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Bundle is a symbolic link. Size scanning does not follow links."
                ])
            }
            guard rootValues.isDirectory == true else { throw CocoaError(.fileReadCorruptFile) }
            size = formatter.string(fromByteCount: try SystemCareManager.allocatedSize(of: application.url))
            sizeError = nil
        } catch {
            size = "Unavailable"
            sizeError = error.localizedDescription
        }
        return SystemCareApplicationMetadata(
            id: application.id,
            size: size,
            sizeError: sizeError,
            lastUsed: values?.contentAccessDate.map { dateStyle.format($0) } ?? "Not available",
            icon: applicationIcon(at: application.url)
        )
    }

    static func applicationIcon(at url: URL) -> CGImage? {
        autoreleasepool {
            let pixels = Int(OnePlusMetrics.cardHeader * 2)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32
            ) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSWorkspace.shared.icon(forFile: url.path)
                .draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            return bitmap.cgImage
        }
    }

    private static func byteFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }
}

struct SystemCareSettingsCards: View {
    @Binding var mode: SystemCareMode

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("Default cleanup mode").onePlusText(.row)
                SystemCareInfo("Guided Cleanup lets you choose locations. Analysis Only disables removal.")
                Spacer()
                OnePlusSelect(choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                              selection: $mode, accessibilityLabel: "Default cleanup mode")
            }
            OnePlusCard {
                OnePlusCardHeader("Safety", systemImage: "lock.shield")
                OnePlusSettingRow("Native cleanup", help: "Moves reviewed items to macOS Trash.") {
                    OnePlusStatus("Recoverable")
                }
                OnePlusSettingRow("Cleanup locations", help: "Caches, user logs, installers, and Xcode build files.") {
                    Text("Known roots").onePlusText(.control)
                }
                OnePlusSettingRow("Mole privileges", help: "Requests appear only in a visible Terminal.", separator: false) {
                    OnePlusStatus("Visible")
                }
            }
        }
    }
}

nonisolated enum SystemCarePage: String, CaseIterable, Identifiable {
    case cleanup
    case storage
    case applications
    case maintenance
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storage: "Storage"
        case .cleanup: "Cleanup"
        case .applications: "Applications"
        case .maintenance: "Maintenance"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .storage: "internaldrive"
        case .cleanup: ToolGlyph.systemCare.symbol
        case .applications: "app.dashed"
        case .maintenance: "wrench.and.screwdriver"
        case .settings: "gearshape"
        }
    }

    var isBottom: Bool { self == .settings }

    static func route(_ path: String) -> (page: Self, tab: String)? {
        switch path {
        case "overview", "cleanup": (.cleanup, "")
        case "storage": (.storage, "")
        case "applications": (.applications, "")
        case "mole", "maintenance", "maintenance/tasks": (.maintenance, "tasks")
        case "history", "maintenance/history": (.maintenance, "history")
        case "settings", "settings/general": (.settings, "general")
        case "about", "settings/about": (.settings, "about")
        default: nil
        }
    }
}

struct SystemCareWindowView: View {
    @State private var manager = SystemCareManager.shared
    @State private var page = SystemCarePage.cleanup
    @AppStorage("systemCare.defaultMode") private var savedMode = SystemCareMode.quick.rawValue
    @State private var maintenanceTab = "tasks"
    @State private var settingsTab = "general"
    @State private var selectedCategory = SystemCareCategoryID.caches
    @State private var cleanupSnapshot = SystemCareTraySnapshot()
    @State private var startupDisk: SystemCareStartupDiskSnapshot?
    @State private var diskLoaded = false
    @State private var categories = Set(SystemCareCategoryID.allCases)
    @State private var storageRows: [SystemCareStorageRow] = []
    @State private var storageRemainder: Int64 = 0
    @State private var applicationRows: [SystemCareApplicationRow] = []
    @State private var applicationIcons: [String: NSImage] = [:]
    @State private var applicationRetryRevision = 0
    @State private var appSearch = ""
    @State private var appSearchFocus = 0
    @State private var selectedApplicationID: String?
    @State private var selectedStorageID: String?
    @State private var previewURL: URL?
    @State private var pendingUninstall: InstalledApplication?
    @State private var showingTrashConfirmation = false
    @State private var showingInstallConfirmation = false
    @State private var pendingOperation: MoleOperation?

    var body: some View {
        removalConfirmations
        .confirmationDialog(
            manager.molePath == nil ? "Install Mole with Homebrew?" : "Update Mole with Homebrew?",
            isPresented: $showingInstallConfirmation
        ) {
            Button(manager.molePath == nil ? "Install" : "Update") { manager.installOrUpdateMole() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            pendingOperation.map { "Run \($0.title) in Terminal?" } ?? "Run maintenance?",
            isPresented: Binding(get: { pendingOperation != nil }, set: { if !$0 { pendingOperation = nil } })
        ) {
            Button("Open Terminal", role: .destructive) {
                guard let operation = pendingOperation else { return }
                manager.openMole(operation, dryRun: false)
                pendingOperation = nil
            }
            Button("Cancel", role: .cancel) { pendingOperation = nil }
        } message: {
            Text(pendingOperation.map { "mo \($0.rawValue) runs in Terminal. Review its plan and privilege requests there." } ?? "")
        }
    }

    private var windowFrame: some View {
        OnePlusWindowRoot(canvas: .systemCare) {
            sidebar
        } content: {
            pageContent
        }
        .background(WindowAccessor(identifier: "system-care"))
        .quickLookPreview($previewURL)
        .buttonStyle(OnePlusButtonStyle())
    }

    private var preparedWindow: some View {
        windowFrame
        .task {
            manager.refresh()
        }
        .task(id: manager.cleanupScanDate) {
            let disk = await Task.detached(priority: .utility) { SystemCareStartupDiskSnapshot.load() }.value
            guard !Task.isCancelled else { return }
            startupDisk = disk
            diskLoaded = true
        }
        .task(id: manager.storageEntries) {
            let entries = manager.storageEntries
            let rows = await Task.detached(priority: .utility) {
                SystemCarePresentationRows.storage(entries)
            }.value
            guard !Task.isCancelled else { return }
            storageRows = rows
            storageRemainder = max(manager.storageTotal - rows.prefix(8).reduce(0) { $0 + $1.entry.size }, 0)
        }
        .task(id: manager.cleanupCandidates) {
            let candidates = manager.cleanupCandidates
            let snapshot = await Task.detached(priority: .utility) {
                SystemCareTraySnapshot.prepare(candidates)
            }.value
            guard !Task.isCancelled else { return }
            cleanupSnapshot = snapshot
        }
        .task(id: applicationRetryRevision) {
            await loadApplications(manager.applications)
        }
        .onDisappear {
            applicationIcons.removeAll()
            applicationRows.removeAll()
        }
        .onChange(of: manager.applications) { applicationRetryRevision &+= 1 }
        .onOpenToolPage("system-care") { pageID in
            guard let route = SystemCarePage.route(pageID) else { return }
            maintenanceTab = route.page == .maintenance ? route.tab : maintenanceTab
            settingsTab = route.page == .settings ? route.tab : settingsTab
            open(route.page)
        }
        .background { shortcuts }
    }

    private var removalConfirmations: some View {
        preparedWindow
        .confirmationDialog(
            "Move selected items to Trash?",
            isPresented: $showingTrashConfirmation
        ) {
            Button("Move \(manager.selectedCandidateIDs.count) Items to Trash", role: .destructive) {
                manager.moveSelectedToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(manager.selectedSize.formattedByteCount) stays recoverable until you empty Trash.")
        }
        .confirmationDialog(
            pendingUninstall.map { "Uninstall \($0.name) in Terminal?" } ?? "Uninstall application?",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            )
        ) {
            Button("Open Uninstall in Terminal", role: .destructive) {
                guard let application = pendingUninstall else { return }
                manager.openMoleUninstall(application, dryRun: false)
                pendingUninstall = nil
            }
            Button("Cancel", role: .cancel) { pendingUninstall = nil }
        } message: {
            Text("Mole shows its removal plan and any privilege request in Terminal.")
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "System Care") {
            ForEach(SystemCarePage.allCases.filter { !$0.isBottom }) { destination in
                OnePlusNavRow(
                    destination.title,
                    systemImage: destination.icon,
                    selected: page == destination
                ) { open(destination) }
            }
        } bottom: {
            ForEach(SystemCarePage.allCases.filter(\.isBottom)) { destination in
                OnePlusNavRow(
                    destination.title,
                    systemImage: destination.icon,
                    selected: page == destination
                ) { open(destination) }
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .storage: storagePage
        case .cleanup: cleanupPage
        case .applications: applicationsPage
        case .maintenance: maintenancePage
        case .settings: settingsPage
        }
    }

    private var cleanupMode: SystemCareMode { SystemCareMode(rawValue: savedMode) ?? .quick }

    private var modeBinding: Binding<SystemCareMode> {
        Binding(get: { cleanupMode }, set: { savedMode = $0.rawValue })
    }

    private var startupDiskCard: some View {
        OnePlusCard(textured: true) {
            SystemCareDiskSummary(disk: startupDisk, loaded: diskLoaded)
                .padding(OnePlusMetrics.cardPadding)
        }
    }

    private var storagePage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(
                title: "Storage",
                subtitle: manager.storageURL?.path ?? "Choose a folder to begin"
            ) {
                if let url = manager.storageURL {
                    OnePlusMenuButton("More", items: [
                        .item(OnePlusPopupMenuItem("Choose Another Folder…", isEnabled: !manager.isWorking) { chooseStorageFolder() }),
                        .item(OnePlusPopupMenuItem("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
                    ])
                    Button("Rescan") { manager.analyze(url, resetBreadcrumbs: true) }
                        .disabled(manager.isWorking)
                } else {
                    Button("Choose Folder…") { chooseStorageFolder() }
                        .buttonStyle(OnePlusButtonStyle(.primary))
                        .disabled(manager.isWorking)
                }
            }
        } footer: {
            statusBanner
            if let url = manager.storageURL {
                HStack {
                    Text(url.path).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }.buttonStyle(OnePlusButtonStyle(.ghost))
                }
            }
        } content: {
            storageContent
        }
    }

    @ViewBuilder
    private var storageContent: some View {
        if let issue = manager.storageIssue {
            OnePlusBanner("\(issue.url.path): \(issue.reason)", tone: .error) {
                Button("Choose Folder…") { chooseStorageFolder() }.disabled(manager.isWorking)
                Button("Retry") { manager.analyze(issue.url, resetBreadcrumbs: true) }.disabled(manager.isWorking)
            }
        }
        if manager.storageURL == nil {
            OnePlusEmptyState(
                "Choose a folder",
                systemImage: "internaldrive",
                caption: "See the folders and files that use the most space."
            ) {
                Button("Choose Folder…") { chooseStorageFolder() }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(manager.isWorking)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            storageBreadcrumbCard
            storageSummaryCard
            storageTableCard
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var storageBreadcrumbCard: some View {
            ScrollView(.horizontal) {
                HStack(spacing: OnePlusMetrics.spacing[2]) {
                    ForEach(manager.storageBreadcrumbs, id: \.path) { url in
                        Button(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) {
                            manager.navigateStorage(to: url)
                        }
                        .buttonStyle(OnePlusButtonStyle(.link))
                        .disabled(manager.isWorking)
                        if url != manager.storageBreadcrumbs.last {
                            Image(systemName: "chevron.right").onePlusText(.caption)
                        }
                    }
                }
            }
            .onePlusScrollIndicators()
    }

    private var storageSummaryCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Folder size", systemImage: "chart.bar.fill") {
                Text(manager.storageTotal.formattedByteCount).onePlusText(.mono)
            }
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[4]) {
                OnePlusSegmentBar(
                    values: storageRows.prefix(8).map { Double($0.entry.size) } + (storageRemainder > 0 ? [Double(storageRemainder)] : []),
                    colors: OnePlusColor.storageSeries
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: OnePlusMetrics.controlColumn))],
                    spacing: OnePlusMetrics.spacing[2]
                ) {
                    ForEach(storageRows.prefix(8)) { row in
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            Circle()
                                .fill(OnePlusColor.storageSeries[row.colorIndex % OnePlusColor.storageSeries.count])
                                .frame(width: OnePlusMetrics.spacing[3], height: OnePlusMetrics.spacing[3])
                            Text(row.entry.name).onePlusText(.caption).lineLimit(1)
                            Spacer()
                            Text(row.size).onePlusText(.mono)
                        }
                    }
                    if storageRemainder > 0 {
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            Circle().fill(OnePlusColor.storageSeries[8 % OnePlusColor.storageSeries.count])
                                .frame(width: OnePlusMetrics.spacing[3], height: OnePlusMetrics.spacing[3])
                            Text("Other entries").onePlusText(.caption)
                            Spacer()
                            Text(storageRemainder.formattedByteCount).onePlusText(.mono)
                        }
                    }
                }
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }

    private var storageTableCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Contents", systemImage: "list.bullet") {
                Text("\(manager.storageFileCount) \(manager.storageCountIsFiles ? "files" : "entries")").onePlusText(.caption)
            }
            if storageRows.isEmpty && !manager.isWorking && manager.storageIssue == nil {
                OnePlusEmptyState("No entries in this folder", systemImage: "folder")
                    .frame(maxHeight: .infinity)
            } else {
                storageTable
            }
        }
    }

    private var storageTable: some View {
        Table(storageRows, selection: $selectedStorageID) {
            TableColumn("Name") { row in
                Label(row.entry.name, systemImage: row.entry.isDirectory ? "folder" : "doc")
                    .lineLimit(1).truncationMode(.middle)
                    .draggable(row.entry.url)
                    .onePlusTableCell(SystemCareStorageLayout.columns[0], position: .first)
            }.width(min: OnePlusMetrics.controlColumn, ideal: SystemCareStorageLayout.columns[0].width)
            TableColumn("Kind") { row in
                Text(row.entry.isDirectory ? "Folder" : "File").onePlusTableCell(SystemCareStorageLayout.columns[1])
            }.width(SystemCareStorageLayout.columns[1].width)
            TableColumn("Size") { row in
                Text(row.size).onePlusTableCell(SystemCareStorageLayout.columns[2], position: .last)
            }.width(SystemCareStorageLayout.columns[2].width)
        }
        .contextMenu(forSelectionType: String.self) { selected in
            if let row = storageRows.first(where: { selected.contains($0.id) }) {
                SystemCareFileActions(url: row.entry.url, previewURL: $previewURL)
            }
        } primaryAction: { selected in openStorageSelection(selected.first) }
        .onKeyPress(.return) { openStorageSelection(selectedStorageID); return .handled }
        .onKeyPress(.space) {
            guard let row = storageRows.first(where: { $0.id == selectedStorageID }) else { return .ignored }
            previewURL = row.entry.url
            return .handled
        }
        .onePlusNativeTable(columns: SystemCareStorageLayout.columns)
    }

    private func openStorageSelection(_ id: String?) {
        guard !manager.isWorking, let row = storageRows.first(where: { $0.id == id }), row.entry.isDirectory else { return }
        manager.analyze(row.entry.url)
    }

    private var cleanupPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Cleanup", subtitle: "Review caches, logs, installers, and Xcode build files.") {
                OnePlusSelect(choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                              selection: modeBinding, accessibilityLabel: "Cleanup mode")
                    .disabled(manager.isWorking)
                if manager.hasCleanupScan {
                    scanButton
                }
            }
        } footer: {
            statusBanner
            if let result = manager.lastTrashResult {
                HStack {
                    if !result.failures.isEmpty {
                        SystemCareTrashFailures(failures: result.failures)
                        Button("Retry Failed Items") { showingTrashConfirmation = true }
                            .disabled(manager.isWorking || cleanupMode == .analysis || manager.selectedCandidateIDs.isEmpty)
                    }
                    Spacer()
                    Text("\(result.movedCount) items moved to Trash, \(result.movedBytes.formattedByteCount) estimated")
                        .onePlusText(.caption)
                }
            }
        } content: {
            cleanupContent
        }
    }

    @ViewBuilder
    private var cleanupContent: some View {
        startupDiskCard
        if manager.cleanupScanOutcome != nil || manager.hasCleanupScan {
            SystemCareScanCoverage(manager: manager)
        }
        if manager.hasCleanupScan {
            cleanupSummary
            if manager.cleanupCandidates.isEmpty {
                OnePlusEmptyState(manager.cleanupScanOutcome == .completed ? "No items in these locations" : "No candidates in retained results",
                                  systemImage: "tray", caption: manager.cleanupScanOutcome == .completed ? "The selected locations were read successfully." : "Review coverage and retry the affected locations.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                    cleanupLocations
                        .frame(width: OnePlusMetrics.controlColumn * 2)
                    cleanupItems
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            scanButton
            cleanupLocations
            Spacer(minLength: 0)
        }
    }

    private var scanButton: some View {
        Button(manager.hasCleanupScan ? "Rescan" : "Scan", systemImage: "arrow.clockwise") {
            manager.scanCleanup(categories: effectiveCategories)
        }
        .buttonStyle(OnePlusButtonStyle(manager.hasCleanupScan ? .neutral : .primary))
        .disabled(manager.isWorking || effectiveCategories.isEmpty)
        .help("Choose cleanup locations, then scan and review the candidates before moving items to Trash.")
        .accessibilityIdentifier("system-care.cleanup.scan")
    }

    private var cleanupSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
            Text("Cleanup candidates").onePlusText(.sectionTitle)
            Text(cleanupSnapshot.isPrepared ? cleanupSnapshot.totalSize.formattedByteCount : "—")
                .onePlusText(.metric)
            Spacer()
            Text("\(manager.cleanupCandidates.count) items / \(cleanupSnapshot.totals.count) locations")
                .onePlusText(.caption)
            Text(manager.cleanupScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .onePlusText(.caption)
            Button("Clear Scan") { manager.clearCleanupScan() }
                .buttonStyle(OnePlusButtonStyle(.ghost))
                .disabled(manager.isWorking)
        }
    }

    private var cleanupLocations: some View {
        OnePlusCard {
            OnePlusCardHeader("Locations", systemImage: "folder")
            ForEach(SystemCareCategoryID.allCases) { category in
                cleanupLocation(category)
            }
            if manager.hasCleanupScan { Spacer(minLength: 0) }
        }
    }

    private func cleanupLocation(_ category: SystemCareCategoryID) -> some View {
        let rows = cleanupSnapshot.groups[category] ?? []
        let coverage = manager.cleanupCoverage.first { $0.category == category }
        return HStack(spacing: OnePlusMetrics.actionSpacing) {
            if cleanupMode == .guided && !manager.hasCleanupScan {
                Toggle("Scan \(category.title)", isOn: Binding(
                    get: { categories.contains(category) },
                    set: { if $0 { categories.insert(category) } else { categories.remove(category) } }
                ))
                .labelsHidden().toggleStyle(OnePlusCheckboxStyle())
                .disabled(manager.isWorking)
            }
            Button { selectedCategory = category } label: {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: category.icon).onePlusText(.row)
                    Text(category.title).onePlusText(.row).lineLimit(1)
                    if manager.hasCleanupScan && coverage?.isComplete != true {
                        SystemCareInfo("Coverage is incomplete or unverified. Open Coverage to inspect this location.")
                    }
                    Spacer(minLength: OnePlusMetrics.spacing[1])
                    if manager.hasCleanupScan {
                        Text(coverage?.didReadRoot == true || !rows.isEmpty ? String(rows.count) : "—").onePlusText(.caption)
                        Text(coverage?.didReadRoot == true || !rows.isEmpty ? (cleanupSnapshot.totals.first { $0.category == category }?.size ?? 0).formattedByteCount : "—")
                            .onePlusText(.mono)
                    }
                }
                .frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(OnePlusButtonStyle(.ghost, horizontalPadding: 0))
            .help(categoryLocation(category))
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.settingRow)
        .onePlusRowHover(selected: manager.hasCleanupScan && selectedCategory == category)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }

    private var cleanupItems: some View {
        OnePlusCard {
            OnePlusCardHeader(selectedCategory.title) {
                Button("Select All") { manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: true) }
                    .buttonStyle(OnePlusButtonStyle(.ghost))
                    .disabled(manager.isWorking)
                Button("Select None") { manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: false) }
                    .buttonStyle(OnePlusButtonStyle(.ghost))
                    .disabled(manager.isWorking)
            }
            HStack {
                Text("Item / location")
                Spacer()
                Text("Size")
            }.onePlusTableHeader()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if (cleanupSnapshot.groups[selectedCategory] ?? []).isEmpty {
                        OnePlusEmptyState("No candidates from this location", systemImage: "folder",
                                          caption: "Review other locations or check scan coverage.")
                    }
                    let rows = cleanupSnapshot.groups[selectedCategory] ?? []
                    ForEach(Array(zip(rows.indices, rows)), id: \.1.id) { index, row in
                        SystemCareCandidateRow(row: row, manager: manager, rowIndex: index)
                    }
                }
            }.onePlusScrollIndicators()
            HStack {
                Text("\(manager.selectedSize.formattedByteCount) selected across all locations")
                    .onePlusText(.caption)
                Spacer()
                Button("Move to Trash", systemImage: "trash") { showingTrashConfirmation = true }
                    .buttonStyle(OnePlusButtonStyle(.destructive))
                    .disabled(manager.isWorking || manager.selectedCandidateIDs.isEmpty || cleanupMode == .analysis)
                    .help(cleanupMode == .analysis ? "Analysis Only disables removal." : "Move reviewed items to macOS Trash.")
            }
            .padding(OnePlusMetrics.cardPadding)
            .overlay(alignment: .top) { OnePlusColor.lineSoft.frame(height: 1) }
        }
    }

    private func categoryLocation(_ category: SystemCareCategoryID) -> String {
        switch category {
        case .caches: "~/Library/Caches"
        case .logs: "~/Library/Logs"
        case .installers: "DMG, PKG, MPKG, ISO, and XIP files in ~/Downloads"
        case .developer: "~/Library/Developer/Xcode/DerivedData"
        }
    }

    private var applicationsPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Applications", subtitle: "Inspect app bundles, then review removal in Terminal.") {
                OnePlusSearchField(prompt: "Search applications", text: $appSearch,
                                   width: OnePlusMetrics.controlColumn * 1.5,
                                   focusTrigger: appSearchFocus,
                                   accessibilityIdentifier: "system-care.applications.search", shortcutHint: "⌘F")
                Button("Refresh", systemImage: "arrow.clockwise") { refreshApplications() }
                    .disabled(manager.isWorking)
            }
        } footer: {
            statusBanner
        } content: {
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                applicationsTable
                applicationDetail
                    .frame(width: OnePlusMetrics.wideControlColumn * 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background { Button("") { appSearchFocus &+= 1 }.keyboardShortcut("f").hidden() }
    }

    private var applicationsTable: some View {
        OnePlusCard {
            OnePlusCardHeader("Installed applications", systemImage: "app.dashed") {
                Text(filteredApplicationRows.count.formatted()).onePlusText(.caption)
            }
            if filteredApplicationRows.isEmpty {
                OnePlusEmptyState(appSearch.isEmpty ? "No applications found" : "No matching applications",
                                  systemImage: "app.dashed", caption: appSearch.isEmpty ? "Refresh to check the Applications folders." : "Try another application name.")
                    .frame(maxHeight: .infinity)
            } else {
                applicationTable
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }

    private var applicationTable: some View {
        Table(filteredApplicationRows, selection: $selectedApplicationID) {
            TableColumn("Application") { row in
                HStack(spacing: OnePlusMetrics.spacing[2]) {
                    applicationIcon(row.application).frame(width: OnePlusMetrics.spacing[7], height: OnePlusMetrics.spacing[7])
                    Text(row.application.name).lineLimit(1).truncationMode(.middle)
                }.onePlusTableCell(SystemCareApplicationLayout.columns[0], position: .first)
            }.width(min: OnePlusMetrics.controlColumn, ideal: SystemCareApplicationLayout.columns[0].width)
            TableColumn("Size") { row in
                Text(row.size ?? "—").onePlusTableCell(SystemCareApplicationLayout.columns[1])
            }.width(SystemCareApplicationLayout.columns[1].width)
            TableColumn("Last accessed") { row in
                Text(row.lastUsed ?? "—").onePlusTableCell(SystemCareApplicationLayout.columns[2], position: .last)
            }.width(SystemCareApplicationLayout.columns[2].width)
        }
        .contextMenu(forSelectionType: String.self) { selected in
            if let row = applicationRows.first(where: { selected.contains($0.id) }) {
                if row.sizeError != nil { Button("Retry Size") { retryApplication(row.application) } }
                SystemCareFileActions(url: row.application.url, previewURL: $previewURL)
                Button("Review Leftovers") { manager.openMoleUninstall(row.application, dryRun: true) }
                    .disabled(manager.isWorking || !manager.canPreviewUninstall || manager.uninstallUnavailableReason(for: row.application) != nil)
            }
        } primaryAction: { selected in selectedApplicationID = selected.first }
        .onePlusNativeTable(columns: SystemCareApplicationLayout.columns)
    }

    private var selectedApplication: InstalledApplication? {
        applicationRows.first(where: { $0.id == selectedApplicationID })?.application
    }

    private var applicationDetail: some View {
        OnePlusPanel {
            if let application = selectedApplication {
                HStack(spacing: OnePlusMetrics.spacing[4]) {
                    applicationIcon(application)
                        .frame(width: OnePlusMetrics.cardHeader, height: OnePlusMetrics.cardHeader)
                    Text(application.name).onePlusText(.sectionTitle).lineLimit(2)
                }
                .padding(OnePlusMetrics.cardPadding)
                VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                    Text(application.url.path).onePlusText(.mono).textSelection(.enabled)
                    let row = applicationRows.first { $0.id == application.id }
                    OnePlusKeyValueRow("Bundle size", value: row?.size ?? "—", monospaced: true)
                    HStack {
                        Text("Last accessed").onePlusText(.caption)
                        SystemCareInfo("File access date reported by macOS. This is not application usage tracking.")
                        Spacer()
                        Text(row?.lastUsed ?? "—").onePlusText(.row)
                    }
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([application.url])
                    }.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    if let error = row?.sizeError {
                        Text(error).onePlusText(.caption, color: OnePlusColor.danger).textSelection(.enabled)
                        Button("Retry Size", systemImage: "arrow.clockwise") { retryApplication(application) }
                            .disabled(manager.isWorking)
                    }
                }.padding(.horizontal, OnePlusMetrics.cardPadding)
                Spacer(minLength: 0)
                applicationActions(application)
            } else {
                OnePlusEmptyState("Select an application", systemImage: "app.dashed",
                                  caption: "Review its bundle size and removal options.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func applicationActions(_ application: InstalledApplication) -> some View {
        let refusal = manager.uninstallUnavailableReason(for: application)
        return VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack {
                Text("Mole uninstall").onePlusText(.cardTitle)
                SystemCareInfo("Review opens a dry run in Terminal. Uninstall and privilege requests stay in Terminal.")
                Spacer()
                if manager.molePath == nil || !manager.canPreviewUninstall {
                    Button("Open Maintenance") { open(.maintenance) }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                }
            }
            if let refusal { Text(refusal).onePlusText(.caption, color: OnePlusColor.danger).textSelection(.enabled) }
            else if !manager.canPreviewUninstall {
                Text("Update Mole to review leftovers.").onePlusText(.caption)
            }
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Button("Review Leftovers", systemImage: "doc.text.magnifyingglass") {
                    manager.openMoleUninstall(application, dryRun: true)
                }.buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(manager.isWorking || refusal != nil || !manager.canPreviewUninstall)
                Button("Uninstall…", systemImage: "trash") { pendingUninstall = application }
                    .buttonStyle(OnePlusButtonStyle(.destructive))
                    .disabled(manager.isWorking || refusal != nil)
            }
        }
        .padding(OnePlusMetrics.cardPadding)
        .overlay(alignment: .top) { OnePlusColor.lineSoft.frame(height: 1) }
    }

    private var maintenancePage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Maintenance", subtitle: "Run advanced tasks in Terminal.") {
                Button(manager.molePath == nil ? "Install Mole…" : "Update Mole…") {
                    showingInstallConfirmation = true
                }.disabled(manager.isWorking)
            }
        } tabs: {
            OnePlusTabStrip(tabs: [OnePlusTab("tasks", "Tasks"), OnePlusTab("history", "History")],
                            selection: $maintenanceTab) {
                if maintenanceTab == "history" {
                    Button("Refresh", systemImage: "arrow.clockwise") { manager.loadHistory() }
                        .disabled(manager.isWorking || manager.molePath == nil)
                }
            }
        } footer: {
            statusBanner
            HStack {
                Button("Manage Whitelist…") { manager.openMoleWhitelist() }
                    .disabled(manager.molePath == nil || manager.isWorking)
                Link("Official Mole Project", destination: URL(string: "https://github.com/tw93/Mole")!)
                    .buttonStyle(OnePlusButtonStyle(.link))
            }
        } content: {
            HStack {
                Text("Mole").onePlusText(.row)
                SystemCareInfo("Mole is optional. Preview and run actions open a visible Terminal.")
                Spacer()
                Text(manager.moleVersion.map { "Version \($0)" } ?? (manager.molePath == nil ? "Not installed" : "Installed"))
                    .onePlusText(.mono)
            }
            if maintenanceTab == "history" { historyCard }
            else { maintenanceTasks }
        }
        .onChange(of: maintenanceTab) { if maintenanceTab == "history" && !manager.isWorking { manager.loadHistory() } }
    }

    private var maintenanceTasks: some View {
        OnePlusCard {
            OnePlusCardHeader("Maintenance tasks", systemImage: "terminal")
            ForEach(MoleOperation.allCases) { operation in
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: operation.icon).onePlusText(.row)
                    Text(operation.title).onePlusText(.row).help(operation.detail)
                    SystemCareInfo(operation.detail)
                    Spacer()
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("Preview") { manager.openMole(operation, dryRun: true) }
                            .buttonStyle(OnePlusButtonStyle(.ghost))
                            .disabled(!manager.canPreview(operation))
                            .help(manager.supportedMolePreviews.contains(operation) ? "mo \(operation.rawValue) --dry-run" : "Update Mole to use a verified preview for this task.")
                        Button("Open Terminal…") { pendingOperation = operation }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(manager.molePath == nil || manager.isWorking)
                }
                .padding(.horizontal, OnePlusMetrics.cardPadding)
                .frame(height: OnePlusMetrics.settingRow)
                .onePlusRowHover()
                .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
            }
        }
    }

    private var historyCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Mole history", systemImage: "clock.arrow.circlepath")
            if manager.history.isEmpty {
                OnePlusEmptyState(manager.molePath == nil ? "Mole is not installed" : "No Mole history",
                                  systemImage: "clock.arrow.circlepath",
                                  caption: manager.molePath == nil ? "Install Mole to view its operation records." : "Run a Mole task, then refresh its history.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let showTime = manager.history.contains { $0.timestamp != nil }
                let showResult = manager.history.contains { $0.result != nil }
                historyCells(nil, showTime: showTime, showResult: showResult).onePlusTableHeader()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(zip(manager.history.indices, manager.history)), id: \.1.id) { index, item in
                            historyCells(item, showTime: showTime, showResult: showResult)
                                .onePlusTableRow(index: index).textSelection(.enabled).help(item.rawPayload)
                        }
                    }
                }.onePlusScrollIndicators()
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }

    private func historyCells(_ item: MoleHistoryItem?, showTime: Bool, showResult: Bool) -> some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Text(item?.title ?? "Operation")
                .frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
            Text(item?.detail ?? "Summary")
                .frame(maxWidth: .infinity, alignment: .leading)
            if showTime {
                Text(item?.timestamp ?? (item == nil ? "Time" : ""))
                    .onePlusText(item == nil ? .tableHeader : .mono)
                    .frame(width: OnePlusMetrics.wideControlColumn, alignment: .trailing)
            }
            if showResult {
                Text(item?.result ?? (item == nil ? "Result" : ""))
                    .onePlusText(item == nil ? .tableHeader : .caption)
                    .frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)
            }
        }.lineLimit(1)
    }

    private var settingsPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Settings", subtitle: "Cleanup defaults and safety")
        } tabs: {
            OnePlusTabStrip(tabs: [OnePlusTab("general", "General"), OnePlusTab("about", "About")],
                            selection: $settingsTab)
        } footer: {
            statusBanner
        } content: {
            if settingsTab == "general" { SystemCareSettingsCards(mode: modeBinding) }
            else { aboutCard }
        }
    }

    private var aboutCard: some View {
        OnePlusCard {
            OnePlusCardHeader("System Care", systemImage: ToolGlyph.systemCare.symbol)
            OnePlusSettingRow("App version") { Text(appVersion).onePlusText(.control) }
            OnePlusSettingRow("Native cleanup") { Text("Included").onePlusText(.control) }
            OnePlusSettingRow("Mole", separator: false) {
                Text(manager.moleVersion.map { "Version \($0)" } ?? (manager.molePath == nil ? "Not installed" : "Version unavailable")).onePlusText(.control)
            }
            Link("Official Mole Project", destination: URL(string: "https://github.com/tw93/Mole")!)
                .buttonStyle(OnePlusButtonStyle(.ghost))
                .padding(OnePlusMetrics.cardPadding)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if manager.isWorking || manager.errorMessage != nil {
            OnePlusBanner(
                manager.errorMessage ?? manager.progressMessage ?? "Working…",
                tone: manager.errorMessage == nil ? .information : .error
            ) {
                if manager.canCancel {
                    Button(manager.isCancelling ? "Canceling…" : "Cancel") { manager.cancel() }
                        .buttonStyle(OnePlusButtonStyle(.ghost))
                        .disabled(manager.isCancelling)
                }
                if manager.isWorking { ProgressView().controlSize(.small) }
            }
        }
    }

    private var shortcuts: some View {
        Group {
            ForEach(SystemCarePage.allCases.indices, id: \.self) { index in
                Button("") { open(SystemCarePage.allCases[index]) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .hidden()
            }
            Button("") { open(.settings) }.keyboardShortcut(",").hidden()
        }
    }

    private var effectiveCategories: Set<SystemCareCategoryID> {
        cleanupMode == .guided ? categories : Set(SystemCareCategoryID.allCases)
    }

    private var filteredApplicationRows: [SystemCareApplicationRow] {
        appSearch.isEmpty ? applicationRows : applicationRows.filter {
            $0.application.name.localizedCaseInsensitiveContains(appSearch)
        }
    }

    @ViewBuilder
    private func applicationIcon(_ application: InstalledApplication) -> some View {
        if let icon = applicationIcons[application.id] {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .foregroundStyle(OnePlusColor.secondary)
                .accessibilityHidden(true)
        }
    }

    private func loadApplications(_ applications: [InstalledApplication]) async {
        let ids = Set(applications.map(\.id))
        applicationIcons = applicationIcons.filter { ids.contains($0.key) }
        let cachedRows = Dictionary(uniqueKeysWithValues: applicationRows.map { ($0.id, $0) })
        applicationRows = applications.map { application in
            let cached = cachedRows[application.id]
            return SystemCareApplicationRow(
                application: application,
                size: cached?.size,
                sizeError: cached?.sizeError,
                lastUsed: cached?.lastUsed
            )
        }
        let pending = applications.filter { cachedRows[$0.id]?.size == nil }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: SystemCareApplicationMetadata.self) { group in
            var next = pending.makeIterator()
            for _ in 0..<min(4, pending.count) {
                guard let application = next.next() else { break }
                group.addTask(priority: .utility) {
                    SystemCarePresentationRows.application(application)
                }
            }
            while let metadata = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let index = applicationRows.firstIndex(where: { $0.id == metadata.id }) {
                    applicationRows[index].size = metadata.size
                    applicationRows[index].sizeError = metadata.sizeError
                    applicationRows[index].lastUsed = metadata.lastUsed
                }
                if let icon = metadata.icon {
                    applicationIcons[metadata.id] = NSImage(cgImage: icon,
                        size: NSSize(width: OnePlusMetrics.cardHeader, height: OnePlusMetrics.cardHeader))
                }
                if let application = next.next() {
                    group.addTask(priority: .utility) {
                        SystemCarePresentationRows.application(application)
                    }
                }
            }
        }
    }

    private func refreshApplications() {
        guard !manager.isWorking else { return }
        for index in applicationRows.indices {
            applicationRows[index].size = nil
            applicationRows[index].sizeError = nil
        }
        manager.refresh()
        applicationRetryRevision &+= 1
    }

    private func retryApplication(_ application: InstalledApplication) {
        guard let index = applicationRows.firstIndex(where: { $0.id == application.id }) else { return }
        applicationRows[index].size = nil
        applicationRows[index].sizeError = nil
        // Reuse the window-owned task so closing the window also cancels retries.
        applicationRetryRevision &+= 1
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    private func open(_ destination: SystemCarePage) {
        page = destination
        if destination == .maintenance && maintenanceTab == "history" && !manager.isWorking { manager.loadHistory() }
    }

    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analyze"
        if panel.runModal() == .OK, let url = panel.url {
            manager.analyze(url, resetBreadcrumbs: true)
        }
    }
}

private extension Int64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

#Preview {
    SystemCareWindowView()
}
