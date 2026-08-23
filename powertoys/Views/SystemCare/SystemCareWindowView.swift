import AppKit
import SwiftUI

private enum SystemCarePage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case storage = "Storage"
    case cleanup = "Cleanup"
    case applications = "Applications"
    case mole = "Mole CLI"
    case history = "History"
    case settings = "Settings"
    case about = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .storage: "chart.pie"
        case .cleanup: "sparkles"
        case .applications: "app.dashed"
        case .mole: "terminal"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
}

struct SystemCareWindowView: View {
    @State private var manager = SystemCareManager.shared
    @State private var page = SystemCarePage.overview
    @State private var cleanupMode = SystemCareMode(rawValue: UserDefaults.standard.string(forKey: "systemCare.defaultMode") ?? "") ?? .quick
    @State private var categories = Set(SystemCareCategoryID.allCases)
    @State private var appSearch = ""
    @State private var selectedApplication: InstalledApplication?
    @State private var showingTrashConfirmation = false
    @State private var showingInstallConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.compactSidebarWidth)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "system-care"))
        .onAppear { manager.refresh() }
        .onDisappear { manager.cancel() }
        .confirmationDialog(
            "Move \(manager.selectedCandidateIDs.count) item(s) to Trash?",
            isPresented: $showingTrashConfirmation
        ) {
            Button("Move to Trash") { manager.moveSelectedToTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(manager.selectedSize.formattedByteCount) can be recovered from Trash until it is emptied.")
        }
        .confirmationDialog(
            manager.molePath == nil ? "Install Mole CLI with Homebrew?" : "Update Mole CLI with Homebrew?",
            isPresented: $showingInstallConfirmation
        ) {
            Button(manager.molePath == nil ? "Install" : "Update") { manager.installOrUpdateMole() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar)
            SidebarTitle(text: "System Care")
            VStack(spacing: 4) {
                ForEach(SystemCarePage.allCases) { item in
                    SidebarRow(icon: item.icon, title: item.rawValue, isSelected: page == item) {
                        page = item
                        if item == .history { manager.loadHistory() }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .overview: overviewPage
        case .storage: storagePage
        case .cleanup: cleanupPage
        case .applications: applicationsPage
        case .mole: molePage
        case .history: historyPage
        case .settings: settingsPage
        case .about: ToolAboutView(toolId: "system-care")
        }
    }

    private var overviewPage: some View {
        WorkspacePage(
            "Overview",
            subtitle: "Storage and cleanup",
            actions: {
                Button("Scan for Cleanup", systemImage: "sparkles") {
                    page = .cleanup
                    manager.scanCleanup(categories: effectiveCategories)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isWorking)
                .accessibilityIdentifier("system-care.overview.scan")
            }
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                overviewCard(
                    icon: "chart.pie",
                    title: "Storage",
                    value: manager.storageURL == nil ? "Ready to analyze" : manager.storageTotal.formattedByteCount,
                    detail: "Choose any folder and drill into its largest contents"
                ) { page = .storage }
                overviewCard(
                    icon: "sparkles",
                    title: "Cleanup",
                    value: manager.cleanupCandidates.isEmpty ? "Nothing scanned" : manager.cleanupCandidates.reduce(0) { $0 + $1.size }.formattedByteCount,
                    detail: "Preview rebuildable data before moving it to Trash"
                ) { page = .cleanup }
                overviewCard(
                    icon: "terminal",
                    title: "Mole CLI",
                    value: manager.moleVersion.map { "Version \($0)" } ?? "Not installed",
                    detail: "Advanced maintenance tools"
                ) { page = .mole }
                overviewCard(
                    icon: "arrow.counterclockwise",
                    title: "Last Cleanup",
                    value: manager.lastRecoveredBytes == 0 ? "No cleanup this session" : manager.lastRecoveredBytes.formattedByteCount,
                    detail: "Items stay recoverable in Trash"
                ) { page = .history }
            }
            statusBanner
        }
    }

    private func overviewCard(icon: String, title: String, value: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var storagePage: some View {
        WorkspacePage(
            "Storage",
            subtitle: manager.storageURL?.path ?? "Choose a folder to begin",
            actions: {
                if let url = manager.storageURL {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Choose Another Folder…") { chooseStorageFolder() }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button("Rescan") { manager.analyze(url, resetBreadcrumbs: true) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button("Choose Folder…") { chooseStorageFolder() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        ) {
            if manager.storageURL == nil {
                ContentUnavailableView(
                    "Choose a Folder",
                    systemImage: "chart.pie",
                    description: Text("Choose a folder to see what uses the most space.")
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    StorageRingView(entries: manager.storageEntries) { entry in
                        if entry.isDirectory { manager.analyze(entry.url) }
                    }
                    .frame(width: 330, height: 330)

                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) {
                                ForEach(manager.storageBreadcrumbs, id: \.path) { url in
                                    Button(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) {
                                        manager.navigateStorage(to: url)
                                    }
                                    .buttonStyle(.borderless)
                                    if url != manager.storageBreadcrumbs.last {
                                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        Text("\(manager.storageTotal.formattedByteCount) · \(manager.storageFileCount.formatted()) entries")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Divider()
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(manager.storageEntries) { entry in
                                    Button {
                                        if entry.isDirectory { manager.analyze(entry.url) }
                                    } label: {
                                        HStack {
                                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                                .foregroundStyle(.secondary)
                                            Text(entry.name).lineLimit(1)
                                            Spacer()
                                            Text(entry.size.formattedByteCount)
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                            if entry.isDirectory { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                                        }
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(minHeight: 280)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            statusBanner
        }
    }

    private var cleanupPage: some View {
        WorkspacePage(
            "Cleanup",
            subtitle: "Review items before moving them to Trash",
            actions: {
                Picker("Mode", selection: $cleanupMode) {
                    ForEach(SystemCareMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 150)

                if manager.cleanupCandidates.isEmpty {
                    Button("Scan") {
                        manager.scanCleanup(categories: effectiveCategories)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isWorking)
                    .accessibilityIdentifier("system-care.cleanup.scan")
                } else {
                    Button("Rescan") {
                        manager.scanCleanup(categories: effectiveCategories)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.isWorking)
                }
            }
        ) {
            if cleanupMode == .guided {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                    ForEach(SystemCareCategoryID.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { categories.contains(category) },
                            set: { selected in
                                if selected { categories.insert(category) }
                                else { categories.remove(category) }
                            }
                        )) {
                            Label(category.title, systemImage: category.icon)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            if !manager.cleanupCandidates.isEmpty {
                HStack {
                    Button("Select All") {
                        manager.cleanupCandidates.forEach { manager.setCandidate($0.id, selected: true) }
                    }
                    Button("Select None") {
                        manager.cleanupCandidates.forEach { manager.setCandidate($0.id, selected: false) }
                    }
                    Spacer()
                    Text("\(manager.selectedCandidateIDs.count) selected · \(manager.selectedSize.formattedByteCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Move to Trash") { showingTrashConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(manager.selectedCandidateIDs.isEmpty || cleanupMode == .analysis)
                }
                .controlSize(.small)
            }

            cleanupResults
            if cleanupMode == .analysis {
                Label("Analysis Only never enables cleanup actions.", systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            statusBanner
        }
    }

    private var effectiveCategories: Set<SystemCareCategoryID> {
        cleanupMode == .guided ? categories : Set(SystemCareCategoryID.allCases)
    }

    private var cleanupResults: some View {
        Group {
            if manager.cleanupCandidates.isEmpty {
                ContentUnavailableView(
                    "No Scan Results",
                    systemImage: "sparkles",
                    description: Text("Run a scan to preview cleanup candidates.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.cleanupCandidates) { candidate in
                            Toggle(isOn: Binding(
                                get: { manager.selectedCandidateIDs.contains(candidate.id) },
                                set: { manager.setCandidate(candidate.id, selected: $0) }
                            )) {
                                HStack {
                                    Image(systemName: candidate.category.icon).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.name).lineLimit(1)
                                        Text(candidate.category.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(candidate.size.formattedByteCount).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .frame(minHeight: 280)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var applicationsPage: some View {
        WorkspacePage("Applications", subtitle: "Review installed applications") {
            SearchField(text: $appSearch, placeholder: "Search applications…")
                .frame(maxWidth: 420)
            if manager.molePath == nil {
                Label("Install Mole CLI to preview or uninstall applications.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredApplications) { application in
                            Button { selectedApplication = application } label: {
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                        .resizable().frame(width: 24, height: 24)
                                    Text(application.name).lineLimit(1)
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color.primary.opacity(selectedApplication == application ? 0.06 : 0))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minWidth: 300)

                VStack(alignment: .leading, spacing: 12) {
                    if let application = selectedApplication {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable().frame(width: 64, height: 64)
                        Text(application.name).font(.system(size: 18, weight: .semibold))
                        Text(application.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Button("Preview Removal") { manager.openMoleUninstall(application, dryRun: true) }
                            .disabled(manager.molePath == nil)
                        Button("Uninstall in Terminal…") { manager.openMoleUninstall(application, dryRun: false) }
                            .disabled(manager.molePath == nil)
                        Text("Mole completes removal in Terminal.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView("Select an Application", systemImage: "app.dashed")
                    }
                    Spacer()
                }
                .padding(16)
                .frame(width: 330)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(minHeight: 430)
        }
    }

    private var filteredApplications: [InstalledApplication] {
        appSearch.isEmpty ? manager.applications : manager.applications.filter {
            $0.name.localizedCaseInsensitiveContains(appSearch)
        }
    }

    private var molePage: some View {
        WorkspacePage(
            "Mole CLI",
            subtitle: "Optional advanced maintenance engine",
            actions: {
                Button(manager.molePath == nil ? "Install with Homebrew…" : "Check for Update…") {
                    showingInstallConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        ) {
            Label(
                manager.moleVersion.map { "Mole \($0) is installed" } ?? "Mole is not installed",
                systemImage: manager.molePath == nil ? "terminal.fill" : "checkmark.circle.fill"
            )
            .foregroundStyle(manager.molePath == nil ? Color.secondary : Color.green)
            .padding(14)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(MoleOperation.allCases) { operation in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(operation.title, systemImage: operation.icon).font(.system(size: 13, weight: .medium))
                        Text(operation.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        HStack {
                            Button("Preview") { manager.openMole(operation, dryRun: true) }
                            Button("Open in Terminal…") { manager.openMole(operation, dryRun: false) }
                        }
                        .disabled(manager.molePath == nil)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            HStack {
                Button("Manage Mole Whitelist…") { manager.openMoleWhitelist() }
                    .disabled(manager.molePath == nil)
                Link("Official Mole Project", destination: URL(string: "https://github.com/tw93/Mole")!)
                Spacer()
            }
            statusBanner
        }
    }

    private var historyPage: some View {
        WorkspacePage(
            "History",
            subtitle: "Recent Mole operations",
            actions: {
                Button("Refresh", systemImage: "arrow.clockwise") { manager.loadHistory() }
                    .controlSize(.small)
                    .disabled(manager.molePath == nil)
            }
        ) {
            if manager.history.isEmpty {
                ContentUnavailableView(
                    manager.molePath == nil ? "Mole Is Not Installed" : "No Mole History",
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(maxWidth: .infinity, minHeight: 380)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.history) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.system(size: 12, weight: .medium))
                                Text(item.detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            statusBanner
        }
    }

    private var settingsPage: some View {
        WorkspacePage("Settings", subtitle: "Defaults and safety") {
            VStack(alignment: .leading, spacing: 12) {
                Text("DEFAULT CLEANUP MODE").utilitySectionHeader()
                Picker("Default mode", selection: Binding(
                    get: { cleanupMode },
                    set: {
                        cleanupMode = $0
                        UserDefaults.standard.set($0.rawValue, forKey: "systemCare.defaultMode")
                    }
                )) {
                    ForEach(SystemCareMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 300)
                Text("Quick scans all supported categories. Guided lets you choose. Analysis Only cannot clean.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text("SAFETY").utilitySectionHeader()
                Label("Native cleanup moves items to macOS Trash", systemImage: "trash")
                Label("Symlinks are not followed while calculating size", systemImage: "link.badge.plus")
                Label("Mole privilege prompts stay in a visible terminal", systemImage: "lock.shield")
            }
            .font(.system(size: 12))
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if manager.isWorking || manager.errorMessage != nil {
            HStack(spacing: 10) {
                if manager.isWorking { ProgressView().controlSize(.small) }
                Image(systemName: manager.errorMessage == nil ? "hourglass" : "exclamationmark.triangle.fill")
                    .foregroundStyle(manager.errorMessage == nil ? Color.secondary : Color.red)
                Text(manager.errorMessage ?? manager.progressMessage ?? "Working…")
                    .font(.system(size: 11))
                Spacer()
                if manager.isWorking { Button("Cancel") { manager.cancel() } }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
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

private struct StorageRingView: View {
    let entries: [StorageEntry]
    let select: (StorageEntry) -> Void

    private var visibleEntries: [StorageEntry] { Array(entries.filter { $0.size > 0 }.prefix(16)) }
    private var total: Double { Double(max(visibleEntries.reduce(0) { $0 + $1.size }, 1)) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let outer = min(size.width, size.height) / 2 - 8
                    let inner = outer * 0.48
                    var start = -Double.pi / 2
                    for (index, entry) in visibleEntries.enumerated() {
                        let sweep = Double(entry.size) / total * Double.pi * 2
                        var path = Path()
                        path.addArc(center: center, radius: outer, startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
                        path.addArc(center: center, radius: inner, startAngle: .radians(start + sweep), endAngle: .radians(start), clockwise: true)
                        path.closeSubpath()
                        context.fill(path, with: .color(Color.accentColor.opacity(0.28 + Double(index % 5) * 0.11)))
                        start += sweep
                    }
                }
                VStack(spacing: 3) {
                    Text(entries.reduce(0) { $0 + $1.size }.formattedByteCount)
                        .font(.system(size: 18, weight: .semibold)).monospacedDigit()
                    Text("visible content").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .contentShape(Circle())
            .gesture(SpatialTapGesture().onEnded { value in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let radius = hypot(dx, dy)
                guard radius > min(geometry.size.width, geometry.size.height) * 0.24 else { return }
                var angle = atan2(dy, dx) + Double.pi / 2
                if angle < 0 { angle += Double.pi * 2 }
                var running = 0.0
                for entry in visibleEntries {
                    running += Double(entry.size) / total * Double.pi * 2
                    if angle <= running { select(entry); return }
                }
            })
        }
        .accessibilityLabel("Storage chart")
        .accessibilityHint("Select a segment to open that folder")
    }
}

private extension Int64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

#Preview {
    SystemCareWindowView().frame(width: 1180, height: 780)
}
