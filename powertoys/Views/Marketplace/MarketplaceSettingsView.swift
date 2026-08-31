//
//  MarketplaceSettingsView.swift
//  powertoys
//

import SwiftUI

struct MarketplaceSettingsView: View {
    private var manager: MarketplaceManager { MarketplaceManager.shared }

    @State private var newSourceText = ""
    @State private var isAddingSource = false
    @State private var addSourceError: String?
    @State private var removalTarget: MarketplaceSource?
    @State private var busyToolIDs: Set<String> = []
    @State private var toolError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourcesSection
                toolsSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 12)
        }
        .thinScrollIndicators()
        .task { await manager.refreshAll() }
        .animation(.easeInOut(duration: 0.15), value: manager.sources)
        .animation(.easeInOut(duration: 0.15), value: manager.receipts)
        .confirmationDialog(
            "Remove \(removalTarget?.displayName ?? "source")?",
            isPresented: removalDialogShown,
            titleVisibility: .visible
        ) {
            removalDialogButtons
        } message: {
            Text("Remove Source Only keeps installed apps usable and reconnects them if the same source is re-added. Remove Source and Associated Apps also quits and deletes every app installed from this source, including its local data.")
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATALOG SOURCES")
                .utilitySectionHeader()

            VStack(alignment: .leading, spacing: 12) {
                addSourceField
                if let addSourceError {
                    Text(addSourceError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if manager.sources.isEmpty {
                    Text("No sources yet. Paste a raw GitHub catalog URL to get started.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.sources) { source in
                        sourceRow(source)
                    }
                }
            }
            .utilitySectionCard()
        }
    }

    private var addSourceField: some View {
        HStack(spacing: 8) {
            TextField("https://raw.githubusercontent.com/user/repo/main/catalog.json", text: $newSourceText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit(addSource)

            SmallActionButton(title: isAddingSource ? "Adding…" : "Add", prominent: true, action: addSource)
                .disabled(isAddingSource || newSourceText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func sourceRow(_ source: MarketplaceSource) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(source.url.absoluteString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let error = source.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if let refreshed = source.lastRefreshed {
                    Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            IconActionButton(systemName: "arrow.clockwise", help: "Refresh this source") {
                Task { await manager.refresh(source.url) }
            }
            IconActionButton(systemName: "trash", help: "Remove this source") {
                removalTarget = source
            }
        }
        .padding(.vertical, 2)
    }

    private var removalDialogShown: Binding<Bool> {
        Binding(
            get: { removalTarget != nil },
            set: { if !$0 { removalTarget = nil } }
        )
    }

    @ViewBuilder
    private var removalDialogButtons: some View {
        if let source = removalTarget {
            Button("Remove Source Only") {
                Task { try? await manager.removeSourceOnly(source.url) }
            }
            Button("Remove Source and Associated Apps", role: .destructive) {
                Task { _ = try? await manager.removeSourceAndApps(source.url) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOOLS")
                .utilitySectionHeader()

            VStack(alignment: .leading, spacing: 14) {
                if let toolError {
                    Text(toolError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if manager.entries.isEmpty {
                    EmptyStateView(icon: "shippingbox", message: "Tools from your catalog sources appear here.")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    ForEach(manager.entries) { entry in
                        toolRow(entry)
                    }
                }
            }
            .utilitySectionCard()
        }
    }

    private func toolRow(_ entry: MarketplaceEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MarketplaceToolIcon(entry: entry)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium))
                    statusBadge(for: entry)
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                versionLine(for: entry)
            }

            Spacer(minLength: 0)

            actionButtons(for: entry)
        }
    }

    @ViewBuilder
    private func statusBadge(for entry: MarketplaceEntry) -> some View {
        switch entry.status {
        case .installed where !entry.sourceAvailable:
            StatusBadge(text: "Source unavailable", icon: "questionmark.circle", tint: .orange)
        case .installed:
            StatusBadge(text: "Installed", icon: "checkmark.circle", tint: .green)
        case .updateAvailable:
            StatusBadge(text: "Update", icon: "arrow.up.circle", tint: .orange)
        case .incompatible:
            StatusBadge(text: "Incompatible", icon: "exclamationmark.circle", tint: .secondary)
        case .available:
            EmptyView()
        }
    }

    @ViewBuilder
    private func versionLine(for entry: MarketplaceEntry) -> some View {
        Group {
            switch entry.status {
            case .updateAvailable:
                Text("Version \(entry.receipt?.version ?? "?") → \(entry.manifest?.version ?? "?") · \(entry.sourceName)")
            case .incompatible:
                Text("Requires MacPowerToys \(entry.manifest?.minHostVersion ?? "?") and macOS \(entry.manifest?.minMacOSVersion ?? "?")")
            default:
                Text("Version \(entry.receipt?.version ?? entry.manifest?.version ?? "?") · \(entry.sourceName)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func actionButtons(for entry: MarketplaceEntry) -> some View {
        if busyToolIDs.contains(entry.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            HStack(spacing: 6) {
                switch entry.status {
                case .available:
                    SmallActionButton(title: "Install", prominent: true) { install(entry) }
                case .updateAvailable:
                    SmallActionButton(title: "Update", prominent: true) { install(entry) }
                    SmallActionButton(title: "Open") { ToolActionRouter.shared.open(toolID: entry.id) }
                    SmallActionButton(title: "Uninstall", destructive: true) { uninstall(entry) }
                case .installed:
                    SmallActionButton(title: "Open") { ToolActionRouter.shared.open(toolID: entry.id) }
                    SmallActionButton(title: "Uninstall", destructive: true) { uninstall(entry) }
                case .incompatible:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Actions

    private func addSource() {
        let text = newSourceText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isAddingSource else { return }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https" else {
            addSourceError = "Enter a valid https:// catalog URL."
            return
        }
        isAddingSource = true
        addSourceError = nil
        Task {
            do {
                try await manager.addSource(url)
                newSourceText = ""
            } catch {
                addSourceError = Self.describe(error)
            }
            isAddingSource = false
        }
    }

    private func install(_ entry: MarketplaceEntry) {
        guard let manifest = entry.manifest,
              let sourceURL = entry.sourceURL,
              let source = manager.sources.first(where: { $0.url == sourceURL })
        else { return }
        busyToolIDs.insert(entry.id)
        toolError = nil
        Task {
            do {
                try await manager.installTool(manifest, from: source)
            } catch {
                toolError = "\(manifest.name): \(Self.describe(error))"
            }
            busyToolIDs.remove(entry.id)
        }
    }

    private func uninstall(_ entry: MarketplaceEntry) {
        guard let receipt = entry.receipt else { return }
        busyToolIDs.insert(entry.id)
        toolError = nil
        Task {
            do {
                try await manager.uninstall(receipt)
            } catch {
                toolError = "\(receipt.name): \(Self.describe(error))"
            }
            busyToolIDs.remove(entry.id)
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case MarketplaceSourceError.invalidURL:
            "Enter a valid https:// catalog URL."
        case MarketplaceSourceError.duplicateSource:
            "This source is already added."
        case let MarketplaceSourceError.httpStatus(code):
            "The server returned HTTP \(code)."
        case MarketplaceSourceError.catalogTooLarge:
            "The catalog exceeds the size limit."
        case let MarketplaceCatalogError.invalidValue(field):
            "The catalog has an invalid value: \(field)."
        case MarketplaceCatalogError.malformedJSON:
            "The catalog is not valid catalog JSON."
        case let MarketplaceCatalogError.unsupportedFormatVersion(version):
            "Catalog format version \(version) is not supported."
        case let MarketplaceCatalogError.duplicateToolID(id):
            "The catalog declares the tool ID \(id) twice."
        case let MarketplaceCatalogError.reservedToolID(id):
            "The tool ID \(id) is reserved by a built-in tool."
        case MarketplaceInstallError.incompatible:
            "This tool requires a newer MacPowerToys or macOS version."
        case MarketplaceInstallError.checksumMismatch:
            "The downloaded archive does not match the catalog checksum."
        case let MarketplaceInstallError.downloadFailed(reason):
            "Download failed: \(reason)."
        case let MarketplaceInstallError.unsafeArchiveEntry(entry):
            "The archive contains an unsafe entry: \(entry)."
        case MarketplaceInstallError.notSingleAppBundle:
            "The archive must contain exactly one .app bundle."
        case let MarketplaceInstallError.teamIDMismatch(team):
            "The app is signed by an unexpected team (\(team))."
        case MarketplaceInstallError.notNotarized:
            "The app is not notarized by Apple."
        case let MarketplaceInstallError.bundleIDMismatch(id):
            "The app has an unexpected bundle identifier (\(id))."
        case MarketplaceInstallError.architectureUnsupported:
            "This app does not support this Mac's architecture."
        case MarketplaceInstallError.appMissing:
            "The installed app is missing. Reinstall it from its source."
        case let MarketplaceInstallError.commandFailed(detail):
            "Verification failed: \(detail)"
        default:
            (error as NSError).localizedDescription
        }
    }
}

// MARK: - Row Components

private struct MarketplaceToolIcon: View {
    let entry: MarketplaceEntry
    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    placeholder
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                placeholder
            }
        }
        .frame(width: 28, height: 28)
        .task(id: entry.id) {
            iconURL = await MarketplaceManager.shared.cachedIconURL(for: entry.id)
            if iconURL == nil, let manifest = entry.manifest {
                iconURL = await MarketplaceManager.shared.fetchIconIfNeeded(for: manifest)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "shippingbox")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct StatusBadge: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct SmallActionButton: View {
    let title: String
    var prominent = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 4))
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .background(background, in: RoundedRectangle(cornerRadius: 4))
    }

    private var foreground: Color {
        if destructive { return .red }
        return prominent ? .primary : .secondary
    }

    private var background: Color {
        prominent ? .accentColor : Color.primary.opacity(0.06)
    }
}

private struct IconActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .help(help)
    }
}

#Preview {
    MarketplaceSettingsView()
        .frame(width: 680, height: 560)
}
