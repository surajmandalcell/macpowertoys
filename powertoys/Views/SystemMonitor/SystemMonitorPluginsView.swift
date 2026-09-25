import SwiftUI

struct SystemMonitorPluginsView: View {
    @AppStorage("systemMonitor.pluginInterval") private var interval = 30
    @State private var plugins: [SystemMonitorPlugin] = []
    @State private var readings: [String: SystemMonitorPluginSample] = [:]
    @State private var errors: [String: String] = [:]
    @State private var isLoading = true
    @State private var reloadID = UUID()
    @State private var showsMarketplace = false

    private var manager: MarketplaceManager { MarketplaceManager.shared }

    var body: some View {
        WorkspacePage("Plugins") {
            Button("Marketplace", systemImage: "shippingbox") { showsMarketplace = true }
            Picker("Refresh", selection: $interval) {
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("60 seconds").tag(60)
            }
            .frame(width: 170)
        } content: {
            if isLoading {
                ProgressView("Finding installed monitor plugins…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if plugins.isEmpty {
                ContentUnavailableView(
                    "No monitor plugins installed",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Install a compatible app from Marketplace. Plugins run only while this page is open.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ForEach(plugins) { plugin in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(plugin.name).utilitySectionHeader()
                        if let error = errors[plugin.id] {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                            ForEach(plugin.manifest.metrics) { metric in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(metric.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text(readings[plugin.id]?.values[metric.id]?.value
                                         ?? (readings[plugin.id] == nil ? "Waiting for data…" : "No reading"))
                                        .font(.system(size: 19, weight: .semibold))
                                        .monospacedDigit()
                                    if let detail = readings[plugin.id]?.values[metric.id]?.detail {
                                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                                .utilitySectionCard()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsMarketplace) { AppSettingsSheet(initialTab: .marketplace) }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in
            reloadID = UUID()
        }
        .onChange(of: showsMarketplace) { _, _ in reloadID = UUID() }
        .task(id: reloadID) { await loadAndPoll() }
    }

    private func loadAndPoll() async {
        isLoading = true
        var installations: [(MarketplaceReceipt, URL)] = []
        for receipt in manager.receipts where MarketplaceCatalog.isIdentifier(receipt.toolID) {
            if let url = await manager.installedAppURL(for: receipt.toolID) {
                installations.append((receipt, url))
            }
        }
        let candidates = installations
        let found = await Task.detached(priority: .utility) {
            candidates.compactMap { SystemMonitorPlugin.load(receipt: $0.0, appURL: $0.1) }
        }.value
        guard !Task.isCancelled else { return }
        plugins = found
        readings = [:]
        errors = [:]
        isLoading = false
        guard !showsMarketplace else { return }

        while !Task.isCancelled, !found.isEmpty {
            for plugin in found {
                do {
                    let sample = try await plugin.sample()
                    guard !Task.isCancelled else { return }
                    readings[plugin.id] = sample
                    errors[plugin.id] = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    readings[plugin.id] = nil
                    errors[plugin.id] = error.localizedDescription
                }
            }
            try? await Task.sleep(for: .seconds(max(interval, 15)))
        }
    }
}
