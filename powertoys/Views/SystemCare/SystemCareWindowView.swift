import AppKit
import OnePlusUI
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
    let iconData: Data?
}

private enum SystemCareApplicationLayout {
    static let sizeColumn = OnePlusMetrics.controlColumn * 0.75
    static let lastUsedColumn = OnePlusMetrics.controlColumn / 2
}

nonisolated enum SystemCarePresentationRows {
    static func storage(_ entries: [StorageEntry]) -> [SystemCareStorageRow] {
        let formatter = byteFormatter()
        return entries.map {
            SystemCareStorageRow(entry: $0, size: formatter.string(fromByteCount: $0.size))
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
        let bytes = allocatedSize(of: application.url)
        let size = bytes.map {
            formatter.string(fromByteCount: $0)
        } ?? "Unavailable"
        let sizeError = bytes == nil
            ? (values?.isSymbolicLink == true
               ? "Bundle is a symbolic link. Size scanning does not follow links."
               : "Bundle files could not be read. Check that the application is available and readable.")
            : nil
        return SystemCareApplicationMetadata(
            id: application.id,
            size: size,
            sizeError: sizeError,
            lastUsed: values?.contentAccessDate.map { dateStyle.format($0) } ?? "Not available",
            iconData: NSWorkspace.shared.icon(forFile: application.url.path).tiffRepresentation
        )
    }

    static func allocatedSize(of root: URL) -> Int64? {
        guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { return nil }
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return nil }
        var total: Int64 = 0
        var foundFile = false
        for case let url as URL in enumerator {
            guard !Task.isCancelled else { return nil }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let (sum, overflow) = total.addingReportingOverflow(bytes)
            total = overflow ? Int64.max : sum
            foundFile = true
        }
        return foundFile && total > 0 ? total : nil
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
            OnePlusCard {
                OnePlusCardHeader("Cleanup", systemImage: "sparkles")
                OnePlusSettingRow(
                    "Default mode",
                    caption: "Guided mode lets you choose categories. Analysis Only cannot remove items.",
                    separator: false
                ) {
                    OnePlusSelect(
                        choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                        selection: $mode,
                        accessibilityLabel: "Default cleanup mode"
                    )
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Safety", systemImage: "lock.shield")
                OnePlusSettingRow("Native cleanup", caption: "Moves reviewed items to macOS Trash.") {
                    OnePlusStatus("Recoverable")
                }
                OnePlusSettingRow("Symbolic links", caption: "Never followed while size is calculated.") {
                    OnePlusStatus("Protected")
                }
                OnePlusSettingRow("Mole privileges", caption: "Requests appear only in a visible Terminal.", separator: false) {
                    OnePlusStatus("Visible")
                }
            }
        }
    }
}

private enum SystemCarePage: String, CaseIterable, Identifiable {
    case overview
    case storage
    case cleanup
    case applications
    case mole
    case history
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .storage: "Storage"
        case .cleanup: "Cleanup"
        case .applications: "Applications"
        case .mole: "Mole"
        case .history: "History"
        case .settings: "Settings"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .storage: "internaldrive"
        case .cleanup: "sparkles"
        case .applications: "app.dashed"
        case .mole: "terminal"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }

    var isBottom: Bool { self == .settings || self == .about }
}

struct SystemCareWindowView: View {
    @State private var manager = SystemCareManager.shared
    @State private var page = SystemCarePage.overview
    @State private var cleanupMode = SystemCareMode.quick
    @State private var categories = Set(SystemCareCategoryID.allCases)
    @State private var storageRows: [SystemCareStorageRow] = []
    @State private var cleanupRows: [SystemCareCleanupRow] = []
    @State private var applicationRows: [SystemCareApplicationRow] = []
    @State private var applicationIcons: [String: NSImage] = [:]
    @State private var applicationRetryRevision = 0
    @State private var appSearch = ""
    @State private var appSearchFocus = 0
    @State private var selectedApplication: InstalledApplication?
    @State private var pendingUninstall: InstalledApplication?
    @State private var showingTrashConfirmation = false
    @State private var showingInstallConfirmation = false

    var body: some View {
        OnePlusWindowRoot(canvas: .systemCare) {
            sidebar
        } content: {
            VStack(spacing: 0) {
                pageContent
                statusBanner
            }
        }
        .background(WindowAccessor(identifier: "system-care"))
        .buttonStyle(OnePlusButtonStyle())
        .task {
            manager.refresh()
            let savedMode = await Task.detached(priority: .utility) {
                UserDefaults.standard.string(forKey: "systemCare.defaultMode")
            }.value
            guard !Task.isCancelled else { return }
            if let savedMode, let mode = SystemCareMode(rawValue: savedMode) {
                cleanupMode = mode
            }
        }
        .task(id: manager.storageEntries) {
            let entries = manager.storageEntries
            let rows = await Task.detached(priority: .utility) {
                SystemCarePresentationRows.storage(entries)
            }.value
            guard !Task.isCancelled else { return }
            storageRows = rows
        }
        .task(id: manager.cleanupCandidates) {
            let candidates = manager.cleanupCandidates
            let rows = await Task.detached(priority: .utility) {
                SystemCarePresentationRows.cleanup(candidates)
            }.value
            guard !Task.isCancelled else { return }
            cleanupRows = rows
        }
        .task(id: manager.applications) {
            await loadApplications(manager.applications)
        }
        .task(id: applicationRetryRevision) {
            guard applicationRetryRevision > 0 else { return }
            await loadApplications(manager.applications)
        }
        .onDisappear { manager.cancel() }
        .onOpenToolPage("system-care") { pageID in
            if let destination = SystemCarePage(rawValue: pageID) { open(destination) }
        }
        .background { shortcuts }
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
        .confirmationDialog(
            manager.molePath == nil ? "Install Mole with Homebrew?" : "Update Mole with Homebrew?",
            isPresented: $showingInstallConfirmation
        ) {
            Button(manager.molePath == nil ? "Install" : "Update") { manager.installOrUpdateMole() }
            Button("Cancel", role: .cancel) {}
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
        case .overview: overviewPage
        case .storage: storagePage
        case .cleanup: cleanupPage
        case .applications: applicationsPage
        case .mole: molePage
        case .history: historyPage
        case .settings: settingsPage
        case .about: aboutPage
        }
    }

    private var overviewPage: some View {
        let reclaimableMetric = SystemCareByteMetric(reclaimableSize)
        let cleanupMetric = SystemCareByteMetric(manager.lastRecoveredBytes)
        return OnePlusPage {
            OnePlusPageHeader(title: "Overview", subtitle: "Storage, cleanup, and maintenance") {
                Button("Scan for Cleanup", systemImage: "sparkles") {
                    page = .cleanup
                    manager.scanCleanup(categories: effectiveCategories)
                }
                .buttonStyle(OnePlusButtonStyle(.primary))
                .disabled(manager.isWorking)
                .accessibilityIdentifier("system-care.overview.scan")
            }
        } content: {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: OnePlusMetrics.cardGap), count: 4),
                spacing: OnePlusMetrics.cardGap
            ) {
                OnePlusMetricTile(
                    "Storage used",
                    systemImage: "internaldrive",
                    value: manager.storageURL == nil ? "—" : manager.storageTotal.formattedByteCount,
                    caption: manager.storageURL?.lastPathComponent ?? "Choose a folder to scan",
                    action: { page = .storage }
                )
                OnePlusMetricTile(
                    "Reclaimable",
                    systemImage: "sparkles",
                    value: manager.hasCleanupScan ? reclaimableMetric.value : "—",
                    unit: manager.hasCleanupScan ? reclaimableMetric.unit : "",
                    caption: manager.hasCleanupScan ? "Latest saved scan" : "Run a cleanup scan",
                    action: { page = .cleanup }
                )
                OnePlusMetricTile(
                    "Applications",
                    systemImage: "app.dashed",
                    value: manager.applications.count.formatted(),
                    caption: "Installed applications",
                    action: { page = .applications }
                )
                OnePlusMetricTile(
                    "Last cleanup",
                    systemImage: "trash",
                    value: manager.lastRecoveredBytes == 0 ? "—" : cleanupMetric.value,
                    unit: manager.lastRecoveredBytes == 0 ? "" : cleanupMetric.unit,
                    caption: manager.lastRecoveredBytes == 0 ? "Review cleanup history" : "Moved to Trash",
                    action: { page = .history }
                )
            }
            recentActivityCard
        }
    }

    private var recentActivityCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Recent activity", systemImage: "clock.arrow.circlepath")
            OnePlusSettingRow("Cleanup scan") {
                Text(manager.cleanupScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Not run")
                    .onePlusText(.control)
            }
            OnePlusSettingRow("Last recovery") {
                Text(manager.lastRecoveredBytes == 0 ? "No items moved" : manager.lastRecoveredBytes.formattedByteCount)
                    .onePlusText(.control)
            }
            OnePlusSettingRow("Mole", separator: false) {
                OnePlusStatus(manager.moleVersion.map { "Version \($0)" } ?? "Not installed",
                              state: manager.molePath == nil ? .offline : .online)
            }
        }
    }

    private var storagePage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(
                title: "Storage",
                subtitle: manager.storageURL?.path ?? "Choose a folder to begin"
            ) {
                if let url = manager.storageURL {
                    Menu {
                        Button("Choose Another Folder…") { chooseStorageFolder() }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    } label: {
                        OnePlusControlLabel {
                            Label("More", systemImage: "ellipsis")
                        }
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    Button("Rescan") { manager.analyze(url, resetBreadcrumbs: true) }
                        .buttonStyle(OnePlusButtonStyle(.primary))
                } else {
                    Button("Choose Folder…") { chooseStorageFolder() }
                        .buttonStyle(OnePlusButtonStyle(.primary))
                }
            }
        } content: {
            if manager.storageURL == nil {
                OnePlusEmptyState(
                    "Choose a folder",
                    systemImage: "internaldrive",
                    caption: "See the folders and files that use the most space."
                ) {
                    Button("Choose Folder…") { chooseStorageFolder() }
                        .buttonStyle(OnePlusButtonStyle(.neutral))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                storageBreadcrumbCard
                storageSummaryCard
                storageTableCard
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var storageBreadcrumbCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Location", systemImage: "folder")
            ScrollView(.horizontal) {
                HStack(spacing: OnePlusMetrics.spacing[2]) {
                    ForEach(Array(manager.storageBreadcrumbs.enumerated()), id: \.element.path) { index, url in
                        Button(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) {
                            manager.navigateStorage(to: url)
                        }
                        .buttonStyle(OnePlusButtonStyle(.link))
                        if index < manager.storageBreadcrumbs.count - 1 {
                            Image(systemName: "chevron.right").onePlusText(.caption)
                        }
                    }
                }
                .padding(OnePlusMetrics.cardPadding)
            }
            .onePlusScrollIndicators()
        }
    }

    private var storageSummaryCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Usage", systemImage: "chart.bar.fill") {
                Text(manager.storageTotal.formattedByteCount).onePlusText(.mono)
            }
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[4]) {
                OnePlusSegmentBar(
                    values: storageRows.prefix(8).map { Double($0.entry.size) },
                    colors: OnePlusColor.storageSeries
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: OnePlusMetrics.controlColumn))],
                    spacing: OnePlusMetrics.spacing[2]
                ) {
                    ForEach(Array(storageRows.prefix(8).enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            Circle()
                                .fill(OnePlusColor.storageSeries[index % OnePlusColor.storageSeries.count])
                                .frame(width: OnePlusMetrics.spacing[3], height: OnePlusMetrics.spacing[3])
                            Text(row.entry.name).onePlusText(.caption).lineLimit(1)
                            Spacer()
                            Text(row.size).onePlusText(.mono)
                        }
                    }
                }
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }

    private var storageTableCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Categories", systemImage: "list.bullet") {
                Text("\(manager.storageFileCount.formatted()) entries").onePlusText(.caption)
            }
            storageTableHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(storageRows) { row in
                        Group {
                            if row.entry.isDirectory {
                                Button { manager.analyze(row.entry.url) } label: { storageRow(row) }
                                    .buttonStyle(OnePlusInteractionStyle())
                            } else {
                                storageRow(row)
                            }
                        }
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([row.entry.url])
                            }
                        }
                    }
                }
            }
            .onePlusScrollIndicators()
        }
    }

    private var storageTableHeader: some View {
        HStack {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Kind").frame(width: OnePlusMetrics.controlColumn, alignment: .leading)
            Text("Size").frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)
        }
        .onePlusTableHeader()
    }

    private func storageRow(_ row: SystemCareStorageRow) -> some View {
        HStack {
            Label(row.entry.name, systemImage: row.entry.isDirectory ? "folder" : "doc")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(row.entry.isDirectory ? "Folder" : "File")
                .frame(width: OnePlusMetrics.controlColumn, alignment: .leading)
            Text(row.size)
                .frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)
        }
        .onePlusTableRow()
    }

    private var cleanupPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Cleanup", subtitle: "Preview every item before removal") {
                OnePlusSelect(
                    choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                    selection: $cleanupMode,
                    accessibilityLabel: "Cleanup mode"
                )
                if manager.hasCleanupScan {
                    Button("Rescan") { manager.scanCleanup(categories: effectiveCategories) }
                        .buttonStyle(OnePlusButtonStyle(.neutral))
                        .disabled(manager.isWorking)
                        .accessibilityIdentifier("system-care.cleanup.scan")
                } else {
                    Button("Scan") { manager.scanCleanup(categories: effectiveCategories) }
                        .buttonStyle(OnePlusButtonStyle(.primary))
                        .disabled(manager.isWorking)
                        .accessibilityIdentifier("system-care.cleanup.scan")
                }
            }
        } content: {
            if cleanupMode == .guided { cleanupCategoriesCard }
            cleanupPreviewCard
                .frame(maxHeight: .infinity, alignment: .top)
            if manager.hasCleanupScan {
                cleanupFooter
                if cleanupMode == .analysis {
                    OnePlusBanner("Analysis Only keeps all removal actions disabled.", tone: .information)
                }
            }
        }
    }

    private var cleanupCategoriesCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Scan categories", systemImage: "checklist")
            ForEach(SystemCareCategoryID.allCases) { category in
                OnePlusSettingRow(category.title, caption: category.detail,
                                  separator: category != SystemCareCategoryID.allCases.last) {
                    Toggle(
                        category.title,
                        isOn: Binding(
                            get: { categories.contains(category) },
                            set: { selected in
                                if selected { categories.insert(category) }
                                else { categories.remove(category) }
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(OnePlusCheckboxStyle())
                }
            }
        }
    }

    private var cleanupPreviewCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Cleanup preview", systemImage: "eye") {
                if manager.hasCleanupScan {
                    Button("All") { manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: true) }
                        .buttonStyle(OnePlusButtonStyle(.link))
                    Button("None") { manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: false) }
                        .buttonStyle(OnePlusButtonStyle(.link))
                }
            }
            if manager.cleanupCandidates.isEmpty {
                OnePlusEmptyState(
                    manager.hasCleanupScan ? "Nothing reclaimable" : "No scan results",
                    systemImage: manager.hasCleanupScan ? "checkmark.circle" : "sparkles",
                    caption: manager.hasCleanupScan ? "The last scan found no cleanup candidates." : "Run a scan to preview cleanup candidates."
                )
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.wideControlColumn)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cleanupRows) { row in
                            HStack(spacing: OnePlusMetrics.spacing[3]) {
                                Toggle(
                                    row.candidate.name,
                                    isOn: Binding(
                                        get: { manager.selectedCandidateIDs.contains(row.id) },
                                        set: { manager.setCandidate(row.id, selected: $0) }
                                    )
                                )
                                .labelsHidden()
                                .toggleStyle(OnePlusCheckboxStyle())
                                Image(systemName: row.candidate.category.icon)
                                    .foregroundStyle(OnePlusColor.secondary)
                                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                                    Text(row.candidate.name).onePlusText(.row).lineLimit(1)
                                    Text(row.candidate.category.title).onePlusText(.caption)
                                }
                                Spacer()
                                Text(row.size).onePlusText(.mono)
                            }
                            .onePlusTableRow()
                        }
                    }
                }
                .onePlusScrollIndicators()
            }
        }
    }

    private var cleanupFooter: some View {
        HStack {
            Text("\(manager.selectedCandidateIDs.count) selected, \(manager.selectedSize.formattedByteCount)")
                .onePlusText(.caption)
            Spacer()
            Button("Move to Trash", systemImage: "trash") { showingTrashConfirmation = true }
                .buttonStyle(OnePlusButtonStyle(.primary))
                .disabled(manager.selectedCandidateIDs.isEmpty || cleanupMode == .analysis)
        }
    }

    private var applicationsPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Applications", subtitle: "Review applications and related files")
        } content: {
            if manager.molePath == nil {
                OnePlusBanner("Install Mole to preview leftovers or uninstall applications.", tone: .warning) {
                    Button("Open Mole") { page = .mole }
                        .buttonStyle(OnePlusButtonStyle(.ghost))
                }
            }
            OnePlusSearchField(
                prompt: "Search applications",
                text: $appSearch,
                width: nil,
                focusTrigger: appSearchFocus,
                accessibilityIdentifier: "system-care.applications.search",
                shortcutHint: "⌘F"
            )
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
            HStack(spacing: OnePlusMetrics.spacing[3]) {
                Text("Application").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: SystemCareApplicationLayout.sizeColumn, alignment: .trailing)
                Text("Last used").frame(width: SystemCareApplicationLayout.lastUsedColumn, alignment: .leading)
            }
            .padding(.horizontal, OnePlusMetrics.spacing[1])
            .onePlusTableHeader()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApplicationRows) { row in
                        let application = row.application
                        Button { selectedApplication = application } label: {
                            HStack(spacing: OnePlusMetrics.spacing[3]) {
                                applicationIcon(application)
                                    .frame(width: OnePlusMetrics.spacing[7], height: OnePlusMetrics.spacing[7])
                                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                                    Text(application.name).lineLimit(1)
                                    if row.sizeError != nil {
                                        Text("Select to review size error").onePlusText(.caption).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.size ?? "—")
                                    .onePlusText(row.size == nil ? .caption : .mono)
                                    .frame(width: SystemCareApplicationLayout.sizeColumn, alignment: .trailing)
                                Text(row.lastUsed ?? "—")
                                    .onePlusText(row.lastUsed == nil ? .caption : .row)
                                    .frame(width: SystemCareApplicationLayout.lastUsedColumn, alignment: .leading)
                            }
                            .padding(.horizontal, OnePlusMetrics.spacing[1])
                            .onePlusTableRow(selected: selectedApplication == application)
                        }
                        .buttonStyle(OnePlusInteractionStyle(selected: selectedApplication == application))
                        .contextMenu {
                            if row.sizeError != nil {
                                Button("Retry Size") { retryApplication(application) }
                            }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([application.url]) }
                            Button("Preview Leftovers") { manager.openMoleUninstall(application, dryRun: true) }
                                .disabled(manager.molePath == nil)
                        }
                    }
                }
            }
            .onePlusScrollIndicators()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var applicationDetail: some View {
        OnePlusPanel {
            if let application = selectedApplication {
                OnePlusCardHeader(application.name)
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[4]) {
                    applicationIcon(application)
                        .frame(width: OnePlusMetrics.spacing[9] * 2, height: OnePlusMetrics.spacing[9] * 2)
                    Text(application.url.path).onePlusText(.mono).textSelection(.enabled)
                    if let row = applicationRows.first(where: { $0.id == application.id }),
                       let error = row.sizeError {
                        OnePlusBanner(error, tone: .warning)
                        Button("Retry Size", systemImage: "arrow.clockwise") { retryApplication(application) }
                            .buttonStyle(OnePlusButtonStyle(.neutral))
                    }
                    Button("Review Leftovers", systemImage: "doc.text.magnifyingglass") {
                        manager.openMoleUninstall(application, dryRun: true)
                    }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(manager.molePath == nil)
                    Button("Uninstall…", systemImage: "trash") { pendingUninstall = application }
                        .buttonStyle(OnePlusButtonStyle(.destructive))
                        .disabled(manager.molePath == nil)
                    Text("Mole opens in Terminal so its plan and privilege prompts stay visible.")
                        .onePlusText(.caption)
                }
                .padding(OnePlusMetrics.cardPadding)
                Spacer(minLength: 0)
            } else {
                OnePlusEmptyState(
                    "Select an application",
                    systemImage: "app.dashed",
                    caption: "Review size, recent use, and removal options."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var molePage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Mole", subtitle: "Advanced maintenance in a visible Terminal") {
                Button(manager.molePath == nil ? "Install with Homebrew…" : "Check for Update…") {
                    showingInstallConfirmation = true
                }
                .buttonStyle(OnePlusButtonStyle(.neutral))
            }
        } footer: {
            HStack {
                Button("Manage Whitelist…") { manager.openMoleWhitelist() }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(manager.molePath == nil)
                Link("Official Mole Project", destination: URL(string: "https://github.com/tw93/Mole")!)
                    .buttonStyle(OnePlusButtonStyle(.link))
            }
        } content: {
            OnePlusBanner(
                manager.moleVersion.map { "Mole \($0) is installed." } ?? "Mole is not installed. Preview and run actions stay disabled.",
                tone: manager.molePath == nil ? .warning : .information
            )
            OnePlusCard {
                OnePlusCardHeader("Maintenance commands", systemImage: "terminal")
                ForEach(MoleOperation.allCases) { operation in
                    HStack(spacing: OnePlusMetrics.spacing[3]) {
                        Image(systemName: operation.icon)
                            .font(.system(size: OnePlusTextRole.sectionTitle.size(for: .regular)))
                            .foregroundStyle(OnePlusColor.secondary)
                            .frame(width: OnePlusTextRole.sectionTitle.size(for: .regular), alignment: .leading)
                        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
                            Text(operation.title).onePlusText(.row)
                            Text(operation.detail).onePlusText(.caption)
                        }
                        Spacer()
                        Button("Preview") { manager.openMole(operation, dryRun: true) }
                            .buttonStyle(OnePlusButtonStyle(.ghost))
                        Button("Open in Terminal…") { manager.openMole(operation, dryRun: false) }
                            .buttonStyle(OnePlusButtonStyle(.neutral))
                    }
                    .padding(.horizontal, OnePlusMetrics.cardPadding)
                    .frame(height: OnePlusMetrics.captionedSettingRow)
                    .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
                    .disabled(manager.molePath == nil)
                }
            }
        }
    }

    private var historyPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "History", subtitle: "Recent Mole operations") {
                Button("Refresh", systemImage: "arrow.clockwise") { manager.loadHistory() }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(manager.molePath == nil)
            }
        } content: {
            OnePlusCard {
                OnePlusCardHeader("Operation history", systemImage: "clock.arrow.circlepath")
                if manager.history.isEmpty {
                    OnePlusEmptyState(
                        manager.molePath == nil ? "Mole is not installed" : "No Mole history",
                        systemImage: "clock.arrow.circlepath",
                        caption: manager.molePath == nil
                            ? "Install Mole to record maintenance operations."
                            : "Run a Mole maintenance command to create history."
                    )
                    .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.wideControlColumn)
                } else {
                    HStack {
                        Text("Operation").frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                        Text("Details").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onePlusTableHeader()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(manager.history) { item in
                                HStack {
                                    Text(item.title).frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                                    Text(item.detail).onePlusText(.mono).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                                }
                                .onePlusTableRow()
                            }
                        }
                    }
                    .onePlusScrollIndicators()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var settingsPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Settings", subtitle: "Cleanup defaults and safety")
        } content: {
            SystemCareSettingsCards(mode: Binding(
                get: { cleanupMode },
                set: {
                    cleanupMode = $0
                    UserDefaults.standard.set($0.rawValue, forKey: "systemCare.defaultMode")
                }
            ))
        }
    }

    private var aboutPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "About", subtitle: appVersion)
        } content: {
            OnePlusCard {
                OnePlusCardHeader("System Care", systemImage: "sparkles")
                OnePlusSettingRow("Native cleanup", caption: "Review and move rebuildable data to Trash.") {
                    OnePlusStatus("Included")
                }
                OnePlusSettingRow("Mole", caption: "Optional advanced maintenance engine.", separator: false) {
                    OnePlusStatus(manager.moleVersion.map { "Version \($0)" } ?? "Not installed",
                                  state: manager.molePath == nil ? .offline : .online)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if manager.isWorking || manager.errorMessage != nil {
            OnePlusBanner(
                manager.errorMessage ?? manager.progressMessage ?? "Working…",
                tone: manager.errorMessage == nil ? .information : .error
            ) {
                if manager.isWorking {
                    Button("Cancel") { manager.cancel() }
                        .buttonStyle(OnePlusButtonStyle(.ghost))
                }
            }
            .padding(.horizontal, OnePlusMetrics.gutter)
            .padding(.bottom, OnePlusMetrics.gutter)
        }
    }

    private var shortcuts: some View {
        Group {
            ForEach(Array(SystemCarePage.allCases.enumerated()), id: \.offset) { index, destination in
                Button("") { open(destination) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .hidden()
            }
            Button("") { open(.settings) }.keyboardShortcut(",").hidden()
        }
    }

    private var reclaimableSize: Int64 {
        manager.cleanupCandidates.reduce(0) { $0 + $1.size }
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
                if let data = metadata.iconData, let icon = NSImage(data: data) {
                    applicationIcons[metadata.id] = icon
                }
                if let application = next.next() {
                    group.addTask(priority: .utility) {
                        SystemCarePresentationRows.application(application)
                    }
                }
            }
        }
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
        if destination == .history { manager.loadHistory() }
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
