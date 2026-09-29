import SwiftUI
import OnePlusUI

struct MarketplaceSettingsView: View {
    private var manager: MarketplaceManager { MarketplaceManager.shared }
    @State private var newSourceText = ""
    @State private var sourceError: String?
    @State private var toolError: String?
    @State private var removalTarget: MarketplaceSource?
    @State private var uninstallTarget: MarketplaceEntry?
    @State private var operation: Task<Void, Never>?
    @State private var busyID: String?
    @State private var refreshing = false

    private var busy: Bool { busyID != nil || refreshing }
    private var installed: [MarketplaceEntry] { manager.entries.filter { $0.receipt != nil } }
    private var available: [MarketplaceEntry] { manager.entries.filter { $0.receipt == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            sourcesCard
            toolCards
            if let toolError { OnePlusBanner(toolError, tone: .error).textSelection(.enabled) }
        }
        .task {
            refreshing = true
            defer { refreshing = false }
            for source in manager.sources {
                guard !Task.isCancelled else { return }
                await manager.refresh(source.url)
            }
        }
        .onDisappear { operation?.cancel(); operation = nil }
        .confirmationDialog(removalTitle, isPresented: removalPresented, titleVisibility: .visible) {
            removalButtons
        } message: {
            Text(removalTarget == nil
                 ? "This quits the tool and removes its installed app and local data."
                 : "Remove the source only to keep its apps. Removing associated apps also quits them and deletes their local data.")
        }
    }

    private var toolCards: some View {
        let layout = installed.isEmpty && available.isEmpty
            ? AnyLayout(HStackLayout(alignment: .top, spacing: OnePlusMetrics.cardGap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: OnePlusMetrics.cardGap))
        return layout {
            toolsCard("Installed tools", entries: installed,
                      empty: "Tools you install from your sources appear here.")
                .frame(maxWidth: .infinity)
            toolsCard("Available tools", entries: available,
                      empty: "Add a catalog source to find more tools.")
                .frame(maxWidth: .infinity)
        }
    }

    private var sourcesCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Sources", systemImage: "shippingbox") {
                if refreshing { ProgressView().controlSize(.small).accessibilityLabel("Refreshing sources") }
            }
            OnePlusSettingRow("Built-in tools", caption: "Included with MacPowerToys") {
                Text("Built-in").onePlusText(.caption)
            }
            ForEach(manager.sources) { source in sourceRow(source) }
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                HStack(alignment: .top, spacing: OnePlusMetrics.actionSpacing) {
                    OnePlusTextField("https://raw.githubusercontent.com/user/repo/main/catalog.json", text: $newSourceText,
                                     error: sourceError, onSubmit: addSource)
                        .accessibilityLabel("Catalog URL")
                    Button(busyID == "add-source" ? "Adding…" : "Add source", action: addSource)
                        .buttonStyle(OnePlusButtonStyle(.primary))
                        .disabled(busy || newSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(OnePlusMetrics.cardPadding)
        }
    }

    private func sourceRow(_ source: MarketplaceSource) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusCatalogMetrics.gap) {
                VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.titleGap) {
                    Text(source.displayName).onePlusText(.cardTitle).lineLimit(1).help(source.displayName)
                    Text(source.url.absoluteString).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                        .help(source.url.absoluteString).textSelection(.enabled)
                    if let refreshed = source.lastRefreshed, source.lastError == nil {
                        Text("Updated \(refreshed.formatted(.relative(presentation: .named)))").onePlusText(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if busyID == source.id { ProgressView().controlSize(.small) }
                Button { run(id: source.id) { await manager.refresh(source.url) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(OnePlusButtonStyle(.icon)).help("Refresh \(source.displayName)")
                    .accessibilityLabel("Refresh \(source.displayName)").disabled(busy)
                Button { removalTarget = source } label: { Image(systemName: "trash") }
                    .buttonStyle(OnePlusButtonStyle(.icon)).help("Remove \(source.displayName)")
                    .accessibilityLabel("Remove \(source.displayName)").disabled(busy)
            }
            if let error = source.lastError { OnePlusBanner(error, tone: .error).textSelection(.enabled) }
        }
        .padding(OnePlusMetrics.cardPadding)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
        .contextMenu {
            Button("Refresh source") { run(id: source.id) { await manager.refresh(source.url) } }.disabled(busy)
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(source.url.absoluteString, forType: .string) }
            Button("Remove source…", role: .destructive) { removalTarget = source }.disabled(busy)
        }
    }

    private func toolsCard(_ title: String, entries: [MarketplaceEntry], empty: String) -> some View {
        OnePlusCard {
            OnePlusCardHeader(title, systemImage: "square.grid.2x2") { OnePlusBadge(entries.count) }
            if entries.isEmpty { OnePlusEmptyState("No tools here", systemImage: "shippingbox", caption: empty) }
            else {
                LazyVStack(spacing: 0) { ForEach(entries) { entry in toolRow(entry) } }
            }
        }
    }

    private func toolRow(_ entry: MarketplaceEntry) -> some View {
        HStack(spacing: OnePlusCatalogMetrics.gap) {
            MarketplaceToolIcon(entry: entry)
            VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.titleGap) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Text(entry.name).onePlusText(.cardTitle).lineLimit(1).help(entry.name)
                    Text(status(entry)).onePlusText(.caption)
                }
                Text(entry.summary).onePlusText(.row).foregroundStyle(OnePlusColor.secondary).lineLimit(2).help(entry.summary)
                Text(version(entry)).onePlusText(.caption).lineLimit(1).help(version(entry))
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                if busyID == entry.id { ProgressView().controlSize(.small).accessibilityLabel("Updating \(entry.name)") }
                actions(entry)
            }.fixedSize()
        }
        .padding(OnePlusMetrics.cardPadding)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
        .contextMenu { actions(entry) }
    }

    @ViewBuilder private func actions(_ entry: MarketplaceEntry) -> some View {
        if entry.status == .available || entry.status == .updateAvailable {
            Button(entry.status == .available ? "Install" : "Update") { install(entry) }
                .buttonStyle(OnePlusButtonStyle(.neutral)).disabled(busy)
        }
        if entry.receipt != nil {
            MainOpenToolButton(toolID: entry.id).disabled(busy)
            Button("Uninstall") { uninstallTarget = entry }
                .buttonStyle(OnePlusButtonStyle(.neutral)).disabled(busy)
        }
    }

    private func status(_ entry: MarketplaceEntry) -> String {
        switch entry.status {
        case .installed: entry.sourceAvailable ? "Installed" : "Source unavailable"
        case .updateAvailable: "Update available"
        case .incompatible: "Incompatible"
        case .available: "Available"
        }
    }

    private func version(_ entry: MarketplaceEntry) -> String {
        switch entry.status {
        case .updateAvailable: "Version \(entry.receipt?.version ?? "?") → \(entry.manifest?.version ?? "?") · \(entry.sourceName)"
        case .incompatible: "Requires MacPowerToys \(entry.manifest?.minHostVersion ?? "?") and macOS \(entry.manifest?.minMacOSVersion ?? "?")"
        default: "Version \(entry.receipt?.version ?? entry.manifest?.version ?? "?") · \(entry.sourceName)"
        }
    }

    private var removalTitle: String {
        if let source = removalTarget { return "Remove \(source.displayName)?" }
        return "Uninstall \(uninstallTarget?.name ?? "tool")?"
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { removalTarget != nil || uninstallTarget != nil }, set: {
            if !$0 { removalTarget = nil; uninstallTarget = nil }
        })
    }

    @ViewBuilder private var removalButtons: some View {
        if let source = removalTarget {
            Button("Remove source only") { run(id: source.id) { try await manager.removeSourceOnly(source.url) } }
            Button("Remove source and associated apps", role: .destructive) {
                run(id: source.id) {
                    let failed = try await manager.removeSourceAndApps(source.url)
                    if !failed.isEmpty { toolError = "Could not remove: " + failed.joined(separator: ", ") }
                }
            }
        } else if let entry = uninstallTarget, let receipt = entry.receipt {
            Button("Uninstall", role: .destructive) { run(id: entry.id) { try await manager.uninstall(receipt) } }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func addSource() {
        guard !busy else { return }
        let text = newSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { sourceError = "Enter a valid https:// catalog URL."; return }
        sourceError = nil
        run(id: "add-source") {
            do { try await manager.addSource(url); newSourceText = "" }
            catch { sourceError = Self.describe(error) }
        }
    }

    private func install(_ entry: MarketplaceEntry) {
        guard let manifest = entry.manifest, let url = entry.sourceURL,
              let source = manager.sources.first(where: { $0.url == url }) else { return }
        run(id: entry.id) { try await manager.installTool(manifest, from: source) }
    }

    private func run(id: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busyID = id
        toolError = nil
        operation = Task {
            defer { busyID = nil; operation = nil }
            do { try Task.checkCancellation(); try await action() }
            catch is CancellationError { }
            catch { if !Task.isCancelled { toolError = Self.describe(error) } }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case MarketplaceSourceError.invalidURL: "Enter a valid https:// catalog URL."
        case MarketplaceSourceError.duplicateSource: "This source is already added."
        case let MarketplaceSourceError.httpStatus(code): "The server returned HTTP \(code)."
        case MarketplaceSourceError.catalogTooLarge: "The catalog exceeds the size limit."
        case let MarketplaceCatalogError.invalidValue(field): "The catalog has an invalid value: \(field)."
        case MarketplaceCatalogError.malformedJSON: "The catalog is not valid catalog JSON."
        case let MarketplaceCatalogError.unsupportedFormatVersion(version): "Catalog format version \(version) is not supported."
        case let MarketplaceCatalogError.duplicateToolID(id): "The catalog declares the tool ID \(id) twice."
        case let MarketplaceCatalogError.reservedToolID(id): "The tool ID \(id) is reserved by a built-in tool."
        case MarketplaceInstallError.incompatible: "This tool requires a newer MacPowerToys or macOS version."
        case MarketplaceInstallError.checksumMismatch: "The downloaded archive does not match the catalog checksum."
        case let MarketplaceInstallError.downloadFailed(reason): "Download failed: \(reason)."
        case let MarketplaceInstallError.unsafeArchiveEntry(entry): "The archive contains an unsafe entry: \(entry)."
        case MarketplaceInstallError.notSingleAppBundle: "The archive must contain exactly one .app bundle."
        case let MarketplaceInstallError.teamIDMismatch(team): "The app is signed by an unexpected team (\(team))."
        case MarketplaceInstallError.notNotarized: "The app is not notarized by Apple."
        case let MarketplaceInstallError.bundleIDMismatch(id): "The app has an unexpected bundle identifier (\(id))."
        case MarketplaceInstallError.architectureUnsupported: "This app does not support this Mac's architecture."
        case MarketplaceInstallError.appMissing: "The installed app is missing. Reinstall it from its source."
        case let MarketplaceInstallError.commandFailed(detail): "Verification failed: \(detail)"
        default: (error as NSError).localizedDescription
        }
    }
}

private struct MarketplaceToolIcon: View {
    let entry: MarketplaceEntry
    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { image in image.resizable().scaledToFit() } placeholder: { placeholder }
            } else { placeholder }
        }
        .toolIconTile(size: OnePlusCatalogMetrics.iconSize)
        .task(id: entry.id) {
            iconURL = await MarketplaceManager.shared.cachedIconURL(for: entry.id)
            if iconURL == nil, let manifest = entry.manifest, !Task.isCancelled {
                iconURL = await MarketplaceManager.shared.fetchIconIfNeeded(for: manifest)
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "shippingbox").onePlusText(.sectionTitle)
            .frame(width: OnePlusCatalogMetrics.iconSize, height: OnePlusCatalogMetrics.iconSize)
            .background(OnePlusColor.raised)
    }
}
