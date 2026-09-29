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
    @State private var cleanupMode = SystemCareMode(
        rawValue: UserDefaults.standard.string(forKey: "systemCare.defaultMode") ?? ""
    ) ?? .quick
    @State private var categories = Set(SystemCareCategoryID.allCases)
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
            ZStack(alignment: .bottom) {
                pageContent
                statusBanner
            }
        }
        .background(WindowAccessor(identifier: "system-care"))
        .buttonStyle(OnePlusButtonStyle())
        .onAppear { manager.refresh() }
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
                    value: manager.storageURL == nil ? "Not scanned" : manager.storageTotal.formattedByteCount,
                    caption: manager.storageURL?.lastPathComponent ?? "Choose a folder",
                    action: { page = .storage }
                )
                OnePlusMetricTile(
                    "Reclaimable",
                    systemImage: "sparkles",
                    value: reclaimableMetric.value,
                    unit: reclaimableMetric.unit,
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
                    value: cleanupMetric.value,
                    unit: cleanupMetric.unit,
                    caption: manager.lastRecoveredBytes == 0 ? "No cleanup this session" : "Moved to Trash",
                    action: { page = .history }
                )
            }
            recentActivityCard
        }
    }

    private var recentActivityCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Recent activity", systemImage: "clock.arrow.circlepath")
            OnePlusSettingRow("Cleanup scan", separator: false) {
                Text(manager.cleanupScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Not run")
                    .onePlusText(.control)
            }
            OnePlusSettingRow("Last recovery", separator: false) {
                Text(manager.lastRecoveredBytes == 0 ? "No items moved" : manager.lastRecoveredBytes.formattedByteCount)
                    .onePlusText(.control)
            }
            OnePlusSettingRow("Mole", separator: false) {
                OnePlusStatus(manager.moleVersion.map { "Version \($0)" } ?? "Not installed",
                              state: manager.molePath == nil ? .offline : .success)
            }
        }
    }

    private var storagePage: some View {
        OnePlusPage {
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
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.wideControlColumn)
            } else {
                storageBreadcrumbCard
                storageSummaryCard
                storageTableCard
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
                    values: manager.storageEntries.prefix(8).map { Double($0.size) },
                    colors: OnePlusColor.storageSeries
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: OnePlusMetrics.controlColumn))],
                    spacing: OnePlusMetrics.spacing[2]
                ) {
                    ForEach(Array(manager.storageEntries.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            Circle()
                                .fill(OnePlusColor.storageSeries[index % OnePlusColor.storageSeries.count])
                                .frame(width: OnePlusMetrics.spacing[3], height: OnePlusMetrics.spacing[3])
                            Text(entry.name).onePlusText(.caption).lineLimit(1)
                            Spacer()
                            Text(entry.size.formattedByteCount).onePlusText(.mono)
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
            ForEach(manager.storageEntries) { entry in
                Group {
                    if entry.isDirectory {
                        Button { manager.analyze(entry.url) } label: { storageRow(entry) }
                            .buttonStyle(OnePlusInteractionStyle())
                    } else {
                        storageRow(entry)
                    }
                }
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                }
            }
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

    private func storageRow(_ entry: StorageEntry) -> some View {
        HStack {
            Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(entry.isDirectory ? "Folder" : "File")
                .frame(width: OnePlusMetrics.controlColumn, alignment: .leading)
            Text(entry.size.formattedByteCount)
                .frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)
        }
        .onePlusTableRow()
    }

    private var cleanupPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Cleanup", subtitle: "Preview every item before removal") {
                OnePlusSelect(
                    choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                    selection: $cleanupMode,
                    accessibilityLabel: "Cleanup mode"
                )
                Button(manager.hasCleanupScan ? "Rescan" : "Scan") {
                    manager.scanCleanup(categories: effectiveCategories)
                }
                .buttonStyle(OnePlusButtonStyle(.neutral))
                .disabled(manager.isWorking)
                .accessibilityIdentifier("system-care.cleanup.scan")
            }
        } content: {
            if cleanupMode == .guided { cleanupCategoriesCard }
            cleanupPreviewCard
            if manager.hasCleanupScan {
                HStack {
                    Text("\(manager.selectedCandidateIDs.count) selected, \(manager.selectedSize.formattedByteCount)")
                        .onePlusText(.caption)
                    Spacer()
                    Button("Move to Trash", systemImage: "trash") { showingTrashConfirmation = true }
                        .buttonStyle(OnePlusButtonStyle(.primary))
                        .disabled(manager.selectedCandidateIDs.isEmpty || cleanupMode == .analysis)
                }
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
                ForEach(manager.cleanupCandidates) { candidate in
                    HStack(spacing: OnePlusMetrics.spacing[3]) {
                        Toggle(
                            candidate.name,
                            isOn: Binding(
                                get: { manager.selectedCandidateIDs.contains(candidate.id) },
                                set: { manager.setCandidate(candidate.id, selected: $0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(OnePlusCheckboxStyle())
                        Image(systemName: candidate.category.icon)
                            .foregroundStyle(OnePlusColor.secondary)
                        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                            Text(candidate.name).onePlusText(.row).lineLimit(1)
                            Text(candidate.category.title).onePlusText(.caption)
                        }
                        Spacer()
                        Text(candidate.size.formattedByteCount).onePlusText(.mono)
                    }
                    .onePlusTableRow()
                }
            }
        }
    }

    private var applicationsPage: some View {
        OnePlusPage {
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
        }
        .background { Button("") { appSearchFocus &+= 1 }.keyboardShortcut("f").hidden() }
    }

    private var applicationsTable: some View {
        OnePlusCard {
            OnePlusCardHeader("Installed applications", systemImage: "app.dashed") {
                Text(filteredApplications.count.formatted()).onePlusText(.caption)
            }
            HStack {
                Text("Application").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)
                Text("Last used").frame(width: OnePlusMetrics.controlColumn, alignment: .leading)
            }
            .onePlusTableHeader()
            ForEach(filteredApplications) { application in
                Button { selectedApplication = application } label: {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable()
                            .frame(width: OnePlusMetrics.controlHeight, height: OnePlusMetrics.controlHeight)
                            .accessibilityHidden(true)
                        Text(application.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        Text(application.formattedSize)
                            .frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)
                        Text(application.formattedLastUsed)
                            .frame(width: OnePlusMetrics.controlColumn, alignment: .leading)
                    }
                    .onePlusTableRow(selected: selectedApplication == application)
                }
                .buttonStyle(OnePlusInteractionStyle(selected: selectedApplication == application))
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([application.url]) }
                    Button("Preview Leftovers") { manager.openMoleUninstall(application, dryRun: true) }
                        .disabled(manager.molePath == nil)
                }
            }
        }
    }

    private var applicationDetail: some View {
        OnePlusCard {
            if let application = selectedApplication {
                OnePlusCardHeader(application.name, systemImage: "app")
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[4]) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                        .resizable()
                        .frame(width: OnePlusMetrics.spacing[9] * 2, height: OnePlusMetrics.spacing[9] * 2)
                    Text(application.url.path).onePlusText(.mono).textSelection(.enabled)
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
            } else {
                OnePlusEmptyState(
                    "Select an application",
                    systemImage: "app.dashed",
                    caption: "Review size, recent use, and removal options."
                )
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.wideControlColumn)
            }
        }
    }

    private var molePage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Mole", subtitle: "Advanced maintenance in a visible Terminal") {
                Button(manager.molePath == nil ? "Install with Homebrew…" : "Check for Update…") {
                    showingInstallConfirmation = true
                }
                .buttonStyle(OnePlusButtonStyle(.neutral))
            }
        } content: {
            OnePlusBanner(
                manager.moleVersion.map { "Mole \($0) is installed." } ?? "Mole is not installed. Preview and run actions stay disabled.",
                tone: manager.molePath == nil ? .warning : .information
            )
            OnePlusCard {
                OnePlusCardHeader("Maintenance commands", systemImage: "terminal")
                ForEach(MoleOperation.allCases) { operation in
                    HStack(spacing: OnePlusMetrics.spacing[4]) {
                        Image(systemName: operation.icon)
                            .foregroundStyle(OnePlusColor.secondary)
                            .frame(width: OnePlusMetrics.controlHeight)
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
            HStack {
                Button("Manage Whitelist…") { manager.openMoleWhitelist() }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(manager.molePath == nil)
                Link("Official Mole Project", destination: URL(string: "https://github.com/tw93/Mole")!)
                    .buttonStyle(OnePlusButtonStyle(.link))
            }
        }
    }

    private var historyPage: some View {
        OnePlusPage {
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
                        systemImage: "clock.arrow.circlepath"
                    )
                    .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.wideControlColumn)
                } else {
                    HStack {
                        Text("Operation").frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                        Text("Details").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onePlusTableHeader()
                    ForEach(manager.history) { item in
                        HStack {
                            Text(item.title).frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                            Text(item.detail).onePlusText(.mono).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        }
                        .onePlusTableRow()
                    }
                }
            }
        }
    }

    private var settingsPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Settings", subtitle: "Cleanup defaults and safety")
        } content: {
            OnePlusCard {
                OnePlusCardHeader("Cleanup", systemImage: "sparkles")
                OnePlusSettingRow(
                    "Default mode",
                    caption: "Guided mode lets you choose categories. Analysis Only cannot remove items.",
                    separator: false
                ) {
                    OnePlusSelect(
                        choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                        selection: Binding(
                            get: { cleanupMode },
                            set: {
                                cleanupMode = $0
                                UserDefaults.standard.set($0.rawValue, forKey: "systemCare.defaultMode")
                            }
                        ),
                        accessibilityLabel: "Default cleanup mode"
                    )
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Safety", systemImage: "lock.shield")
                OnePlusSettingRow("Native cleanup", caption: "Moves reviewed items to macOS Trash.", separator: false) {
                    OnePlusStatus("Recoverable", state: .success)
                }
                OnePlusSettingRow("Symbolic links", caption: "Never followed while size is calculated.", separator: false) {
                    OnePlusStatus("Protected", state: .success)
                }
                OnePlusSettingRow("Mole privileges", caption: "Requests appear only in a visible Terminal.", separator: false) {
                    OnePlusStatus("Visible", state: .success)
                }
            }
        }
    }

    private var aboutPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "About", subtitle: "System Care")
        } content: {
            OnePlusCard {
                OnePlusCardHeader("System Care", systemImage: "sparkles")
                OnePlusSettingRow("Native cleanup", caption: "Review and move rebuildable data to Trash.") {
                    OnePlusStatus("Included", state: .success)
                }
                OnePlusSettingRow("Mole", caption: "Optional advanced maintenance engine.", separator: false) {
                    OnePlusStatus(manager.moleVersion.map { "Version \($0)" } ?? "Not installed",
                                  state: manager.molePath == nil ? .offline : .success)
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
            .padding(OnePlusMetrics.gutter)
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

    private var filteredApplications: [InstalledApplication] {
        appSearch.isEmpty ? manager.applications : manager.applications.filter {
            $0.name.localizedCaseInsensitiveContains(appSearch)
        }
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

private extension InstalledApplication {
    var formattedSize: String {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        guard let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize else { return "Unknown" }
        return Int64(size).formattedByteCount
    }

    var formattedLastUsed: String {
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey])
        return values?.contentAccessDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
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
