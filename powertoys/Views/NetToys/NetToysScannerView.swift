import AppKit
import Observation
import OnePlusUI
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum NetToysResultFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case alive = "Alive"
    case openPorts = "Open Ports"

    var id: String { rawValue }
}

nonisolated enum NetToysExportFormat: String, CaseIterable, Identifiable, Sendable {
    case savedResults = "NetToys Results"
    case csv = "CSV"
    case text = "Text"
    case xml = "XML"
    case ipPorts = "IP and Port"
    case sql = "SQL"

    var id: String { rawValue }

    var canAppend: Bool {
        switch self {
        case .csv, .text, .ipPorts, .sql: true
        case .savedResults, .xml: false
        }
    }

    var fileExtension: String {
        switch self {
        case .savedResults: "nettoys"
        case .csv: "csv"
        case .text, .ipPorts: "txt"
        case .xml: "xml"
        case .sql: "sql"
        }
    }
}

extension NetToysScanResult {
    nonisolated var sortAddress: UInt32 { address.rawValue }
    nonisolated var statusTitle: String { isReachable ? "Up" : "Down" }
    nonisolated var responseTitle: String { responseMilliseconds.map { String(format: "%.1f", $0) } ?? "" }
    nonisolated var hostnameTitle: String { hostname ?? "" }
    nonisolated var macTitle: String { macAddress ?? (isReachable ? "macOS restricted" : "") }
    nonisolated var macHelp: String {
        macAddress == nil && isReachable
            ? "Enable MAC Access in NetToys Settings, then rescan this neighboring device."
            : ""
    }
    nonisolated var vendorTitle: String { vendor ?? "" }
    nonisolated var portsTitle: String { openPorts.map(String.init).joined(separator: ", ") }
    nonisolated var filteredPortsTitle: String { filteredPorts?.map(String.init).joined(separator: ", ") ?? "" }
    nonisolated var ttlTitle: String { ttl.map(String.init) ?? "" }
    nonisolated var packetLossTitle: String {
        packetLossPercent.map { String(format: "%.1f", $0) } ?? ""
    }
    nonisolated var httpServerTitle: String { httpServer ?? "" }
    nonisolated var httpProxyTitle: String { httpProxy ?? "" }
    nonisolated var netBIOSTitle: String { netBIOSName ?? "" }
    nonisolated var customTextTitle: String { customText ?? "" }
    nonisolated var commentTitle: String { comment ?? "" }
}

@Observable
@MainActor
final class NetToysScannerViewModel {
    private static let preferencesKey = "nettoys.scanner.preferences"
    private static let livenessPreferencesKey = "nettoys.scanner.liveness-preferences"
    private static let openersKey = "nettoys.scanner.openers"
    private static let targetKey = "nettoys.scanner.target"
    private static let portKey = "nettoys.scanner.ports"
    private static let filterKey = "nettoys.scanner.filter"
    private static let searchKey = "nettoys.scanner.search"
    private static let sortKey = "nettoys.scanner.sort"

    private enum SortField: String, Codable {
        case address, status, response, ttl, loss, hostname, mac, vendor
        case netBIOS, openPorts, filteredPorts, httpServer, httpProxy, customText, comment
    }

    private struct SavedSort: Codable {
        let field: SortField
        let order: SortOrder
    }

    var targetInput: String {
        didSet { defaults.set(targetInput, forKey: Self.targetKey) }
    }
    var portInput = "22, 80, 443" {
        didSet { defaults.set(portInput, forKey: Self.portKey) }
    }
    var results: [NetToysScanResult] = []
    var filter = NetToysResultFilter.all {
        didSet { defaults.set(filter.rawValue, forKey: Self.filterKey) }
    }
    var searchText = "" {
        didSet { defaults.set(searchText, forKey: Self.searchKey) }
    }
    var completed = 0
    var total = 0
    var lastDuration: TimeInterval?
    var errorMessage: String?
    var isScanning = false
    var isImporting = false
    var isExporting = false
    var timeoutMilliseconds = 750
    var concurrency = 64
    var launchDelayMilliseconds = 0
    var collectPingDetails = false
    var pingProbeCount = 2
    var livenessMethod = NetToysLivenessMethod.tcp
    var pingTimeoutMilliseconds = 750
    var adaptiveTCPTimeout = false
    var scanUnresponsiveHosts = true
    var detectHTTPServer = false
    var detectHTTPProxy = false
    var detectNetBIOS = false
    var customTextEnabled = false
    var customTextPort = 22
    var customTextRequest = ""
    var customTextPattern = ""
    var favoriteTargets = NetToysScannerStore.favoriteTargets()
    var annotations = NetToysScannerStore.annotations()
    var openers = NetToysOpener.defaults
    var selection = Set<String>()
    var sortOrder = [KeyPathComparator(\NetToysScanResult.sortAddress)] {
        didSet {
            defaults.set(try? JSONEncoder().encode(sortOrder.compactMap(Self.savedSort)), forKey: Self.sortKey)
        }
    }

    private let defaults: UserDefaults
    private let scanner = NetToysScanner()
    private var scanTask: Task<Void, Never>?
    private var scanIdentifier: UUID?
    private var resultIndices: [String: Int] = [:]

    init(
        archive: NetToysScanArchive = NetToysScannerStore.archive(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        let latestRun = archive.runs.last
        targetInput = defaults.string(forKey: Self.targetKey)
            ?? latestRun?.target
            ?? LocalIPv4Network.active()?.cidr
            ?? "192.168.1.0/24"
        results = latestRun?.results ?? []
        lastDuration = latestRun?.duration
        completed = results.count
        total = results.count
        filter = defaults.string(forKey: Self.filterKey).flatMap(NetToysResultFilter.init(rawValue:)) ?? .all
        searchText = defaults.string(forKey: Self.searchKey) ?? ""
        if let data = defaults.data(forKey: Self.preferencesKey),
           let preferences = try? JSONDecoder().decode(NetToysScannerPreferences.self, from: data) {
            portInput = preferences.portInput
            timeoutMilliseconds = min(max(preferences.timeoutMilliseconds, 100), 5_000)
            concurrency = min(max(preferences.concurrency, 1), 256)
            launchDelayMilliseconds = min(max(preferences.launchDelayMilliseconds, 0), 100)
            collectPingDetails = preferences.collectPingDetails
            pingProbeCount = min(max(preferences.pingProbeCount, 1), 5)
            detectHTTPServer = preferences.detectHTTPServer
            detectHTTPProxy = preferences.detectHTTPProxy
            detectNetBIOS = preferences.detectNetBIOS
            customTextEnabled = preferences.customTextEnabled
            customTextPort = min(max(preferences.customTextPort, 1), 65_535)
            customTextRequest = preferences.customTextRequest
            customTextPattern = preferences.customTextPattern
        }
        portInput = defaults.string(forKey: Self.portKey) ?? portInput
        if let data = defaults.data(forKey: Self.livenessPreferencesKey),
           let preferences = try? JSONDecoder().decode(NetToysLivenessPreferences.self, from: data) {
            livenessMethod = preferences.method
            pingTimeoutMilliseconds = min(max(preferences.pingTimeoutMilliseconds, 100), 5_000)
            adaptiveTCPTimeout = preferences.adaptiveTCPTimeout
            scanUnresponsiveHosts = preferences.scanUnresponsiveHosts
        }
        if let data = defaults.data(forKey: Self.openersKey),
           let saved = try? JSONDecoder().decode([NetToysOpener].self, from: data),
           saved.count <= 20,
           Set(saved.map(\.id)).count == saved.count,
           Set(saved.map {
               $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
           }).count == saved.count,
           saved.allSatisfy({ (try? $0.validate()) != nil }) {
            openers = saved
        }
        if let data = defaults.data(forKey: Self.sortKey),
           let saved = try? JSONDecoder().decode([SavedSort].self, from: data) {
            let restored = saved.map(Self.comparator)
            if !restored.isEmpty { sortOrder = restored }
        }
        replaceResults(results)
    }

    private static func savedSort(
        _ comparator: KeyPathComparator<NetToysScanResult>
    ) -> SavedSort? {
        let keyPath = comparator.keyPath
        let field: SortField?
        if keyPath == \NetToysScanResult.sortAddress { field = .address }
        else if keyPath == \NetToysScanResult.statusTitle { field = .status }
        else if keyPath == \NetToysScanResult.responseTitle { field = .response }
        else if keyPath == \NetToysScanResult.ttlTitle { field = .ttl }
        else if keyPath == \NetToysScanResult.packetLossTitle { field = .loss }
        else if keyPath == \NetToysScanResult.hostnameTitle { field = .hostname }
        else if keyPath == \NetToysScanResult.macTitle { field = .mac }
        else if keyPath == \NetToysScanResult.vendorTitle { field = .vendor }
        else if keyPath == \NetToysScanResult.netBIOSTitle { field = .netBIOS }
        else if keyPath == \NetToysScanResult.portsTitle { field = .openPorts }
        else if keyPath == \NetToysScanResult.filteredPortsTitle { field = .filteredPorts }
        else if keyPath == \NetToysScanResult.httpServerTitle { field = .httpServer }
        else if keyPath == \NetToysScanResult.httpProxyTitle { field = .httpProxy }
        else if keyPath == \NetToysScanResult.customTextTitle { field = .customText }
        else if keyPath == \NetToysScanResult.commentTitle { field = .comment }
        else { field = nil }
        return field.map { SavedSort(field: $0, order: comparator.order) }
    }

    private static func comparator(
        _ saved: SavedSort
    ) -> KeyPathComparator<NetToysScanResult> {
        switch saved.field {
        case .address: KeyPathComparator(\NetToysScanResult.sortAddress, order: saved.order)
        case .status: KeyPathComparator(\NetToysScanResult.statusTitle, order: saved.order)
        case .response: KeyPathComparator(\NetToysScanResult.responseTitle, order: saved.order)
        case .ttl: KeyPathComparator(\NetToysScanResult.ttlTitle, order: saved.order)
        case .loss: KeyPathComparator(\NetToysScanResult.packetLossTitle, order: saved.order)
        case .hostname: KeyPathComparator(\NetToysScanResult.hostnameTitle, order: saved.order)
        case .mac: KeyPathComparator(\NetToysScanResult.macTitle, order: saved.order)
        case .vendor: KeyPathComparator(\NetToysScanResult.vendorTitle, order: saved.order)
        case .netBIOS: KeyPathComparator(\NetToysScanResult.netBIOSTitle, order: saved.order)
        case .openPorts: KeyPathComparator(\NetToysScanResult.portsTitle, order: saved.order)
        case .filteredPorts: KeyPathComparator(\NetToysScanResult.filteredPortsTitle, order: saved.order)
        case .httpServer: KeyPathComparator(\NetToysScanResult.httpServerTitle, order: saved.order)
        case .httpProxy: KeyPathComparator(\NetToysScanResult.httpProxyTitle, order: saved.order)
        case .customText: KeyPathComparator(\NetToysScanResult.customTextTitle, order: saved.order)
        case .comment: KeyPathComparator(\NetToysScanResult.commentTitle, order: saved.order)
        }
    }

    func savePreferences() {
        let value = NetToysScannerPreferences(
            portInput: portInput,
            timeoutMilliseconds: timeoutMilliseconds,
            concurrency: concurrency,
            launchDelayMilliseconds: launchDelayMilliseconds,
            collectPingDetails: collectPingDetails,
            pingProbeCount: pingProbeCount,
            detectHTTPServer: detectHTTPServer,
            detectHTTPProxy: detectHTTPProxy,
            detectNetBIOS: detectNetBIOS,
            customTextEnabled: customTextEnabled,
            customTextPort: customTextPort,
            customTextRequest: customTextRequest,
            customTextPattern: customTextPattern
        )
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
        let liveness = NetToysLivenessPreferences(
            method: livenessMethod,
            pingTimeoutMilliseconds: pingTimeoutMilliseconds,
            adaptiveTCPTimeout: adaptiveTCPTimeout,
            scanUnresponsiveHosts: scanUnresponsiveHosts
        )
        if let data = try? JSONEncoder().encode(liveness) {
            defaults.set(data, forKey: Self.livenessPreferencesKey)
        }
    }

    func saveOpeners(_ proposed: [NetToysOpener]) throws {
        guard proposed.count <= 20 else { throw NetToysOpener.ValidationError.tooManyOpeners }
        try proposed.forEach { try $0.validate() }
        let names = proposed.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(names).count == names.count else { throw NetToysOpener.ValidationError.duplicateName }
        var normalized = proposed
        for index in normalized.indices {
            normalized[index].name = normalized[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        openers = normalized
        defaults.set(try JSONEncoder().encode(openers), forKey: Self.openersKey)
    }

    var visibleResults: [NetToysScanResult] {
        results.filter { result in
            let includes: Bool
            switch filter {
            case .all: includes = true
            case .alive: includes = result.isReachable
            case .openPorts: includes = !result.openPorts.isEmpty
            }
            guard includes else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return ([
                result.address.description, result.hostnameTitle, result.macTitle, result.vendorTitle,
                result.portsTitle, result.httpServerTitle, result.httpProxyTitle,
                result.netBIOSTitle, result.customTextTitle, result.commentTitle
            ])
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func start(targets override: [IPv4Address]? = nil) {
        guard !isScanning, !isImporting else { return }
        _ = NetToysNeighborServiceManager.shared.enable()
        do {
            var defaultPorts = try PortList.parse(portInput)
            if customTextEnabled {
                let probe = NetToysCustomTextProbe(
                    port: UInt16(customTextPort),
                    request: customTextRequest,
                    responsePattern: customTextPattern
                )
                try probe.validate()
                defaultPorts = Array(Set(defaultPorts + [probe.port])).sorted()
            }
            let sourceTarget = override == nil
                ? targetInput
                : override?.map(\.description).joined(separator: ", ") ?? ""
            errorMessage = nil
            completed = 0
            total = override?.count ?? 0
            isScanning = true
            let identifier = UUID()
            scanIdentifier = identifier
            let started = Date()
            scanTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let targets = if let override {
                        override.map { NetToysScanTarget(address: $0, ports: defaultPorts) }
                    } else {
                        try await NetToysTargetResolver.resolve(targetInput, defaultPorts: defaultPorts)
                    }
                    guard !targets.isEmpty else {
                        throw NetToysTargetInput.ParseError.invalid(sourceTarget)
                    }
                    guard scanIdentifier == identifier else { return }
                    if override == nil {
                        replaceResults([])
                        selection.removeAll()
                    }
                    total = targets.count
                    let values = await scanner.scan(
                        targets: targets,
                        timeoutMilliseconds: timeoutMilliseconds,
                        concurrency: concurrency,
                        collectPingDetails: collectPingDetails,
                        pingProbeCount: pingProbeCount,
                        livenessMethod: livenessMethod,
                        pingTimeoutMilliseconds: pingTimeoutMilliseconds,
                        adaptiveTCPTimeout: adaptiveTCPTimeout,
                        scanUnresponsiveHosts: scanUnresponsiveHosts,
                        launchDelayMilliseconds: launchDelayMilliseconds,
                        fetchOptions: fetchOptions,
                        progress: { [weak self] completed, total in
                            Task { @MainActor [weak self] in
                                guard self?.scanIdentifier == identifier else { return }
                                self?.completed = completed
                                self?.total = total
                            }
                        },
                        update: { [weak self] result in
                            Task { @MainActor [weak self] in
                                guard self?.scanIdentifier == identifier else { return }
                                self?.applyScanUpdate(result)
                            }
                        }
                    )
                    guard !Task.isCancelled, scanIdentifier == identifier else { return }
                    values.forEach(applyScanUpdate)
                    let duration = Date().timeIntervalSince(started)
                    lastDuration = duration
                    isScanning = false
                    scanIdentifier = nil
                    scanTask = nil
                    try NetToysScannerStore.record(NetToysScanRun(
                        target: sourceTarget,
                        ports: Set(targets.flatMap(\.ports)).sorted(),
                        duration: duration,
                        results: values
                    ))
                } catch {
                    guard !Task.isCancelled, scanIdentifier == identifier else { return }
                    errorMessage = error.localizedDescription
                    isScanning = false
                    scanIdentifier = nil
                    scanTask = nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var fetchOptions: NetToysFetchOptions {
        NetToysFetchOptions(
            detectHTTPServer: detectHTTPServer,
            detectHTTPProxy: detectHTTPProxy,
            detectNetBIOS: detectNetBIOS,
            customTextProbe: customTextEnabled && !customTextPattern.isEmpty
                ? NetToysCustomTextProbe(
                    port: UInt16(customTextPort),
                    request: customTextRequest,
                    responsePattern: customTextPattern
                )
                : nil
        )
    }

    func cancel() {
        scanIdentifier = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func importTargets() {
        guard !isScanning, !isImporting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImporting = true
        Task { [weak self] in
            do {
                let targets = try await Task.detached(priority: .userInitiated) {
                    try NetToysFileImport.targets(from: url)
                }.value
                self?.targetInput = targets
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isImporting = false
        }
    }

    func export(_ format: NetToysExportFormat, rows: [NetToysScanResult]) {
        guard !rows.isEmpty, !isExporting else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetToys Scan.\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    switch format {
                    case .savedResults:
                        try NetToysScanExport.savedResults(rows).write(to: url, options: .atomic)
                    case .csv:
                        try NetToysScanExport.csv(rows).write(to: url, atomically: true, encoding: .utf8)
                    case .text:
                        try NetToysScanExport.text(rows).write(to: url, atomically: true, encoding: .utf8)
                    case .xml:
                        try NetToysScanExport.xml(rows).write(to: url, atomically: true, encoding: .utf8)
                    case .ipPorts:
                        try NetToysScanExport.ipPorts(rows).write(to: url, atomically: true, encoding: .utf8)
                    case .sql:
                        try NetToysScanExport.sql(rows).write(to: url, atomically: true, encoding: .utf8)
                    }
                }.value
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isExporting = false
        }
    }

    func append(_ format: NetToysExportFormat, rows: [NetToysScanResult]) {
        guard format.canAppend, !rows.isEmpty, !isExporting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Append"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    let isEmpty = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == 0
                    let value = switch format {
                    case .csv: NetToysScanExport.csv(rows, includeHeader: isEmpty)
                    case .text: NetToysScanExport.text(rows)
                    case .ipPorts: NetToysScanExport.ipPorts(rows)
                    case .sql: NetToysScanExport.sql(rows, includeSchema: isEmpty)
                    case .savedResults, .xml: ""
                    }
                    try NetToysScanExport.append(value, to: url)
                }.value
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isExporting = false
        }
    }

    func loadResults() {
        guard !isScanning, !isImporting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "nettoys") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImporting = true
        Task { [weak self] in
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    let data = try NetToysFileImport.read(
                        url,
                        maximumBytes: NetToysFileImport.resultsByteLimit
                    )
                    return try NetToysScanImport.savedResults(data)
                }.value
                self?.replaceResults(results)
                self?.lastDuration = nil
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isImporting = false
        }
    }

    func removeResults(ids: Set<String>) {
        results.removeAll { ids.contains($0.id) }
        rebuildResultIndices()
    }

    func toggleFavoriteTarget() {
        let value = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if favoriteTargets.contains(value) {
            favoriteTargets.removeAll { $0 == value }
        } else {
            favoriteTargets.append(value)
        }
        do {
            try NetToysScannerStore.saveFavoriteTargets(favoriteTargets)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateRandomTargets(cidr: String, count: Int) {
        do {
            targetInput = try IPv4Targets.random(in: cidr, count: count)
                .map(\.description)
                .joined(separator: ", ")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func annotation(for address: String) -> NetToysHostAnnotation {
        annotations[address] ?? NetToysHostAnnotation()
    }

    func saveAnnotation(_ annotation: NetToysHostAnnotation, for address: String) {
        if annotation.comment.isEmpty, !annotation.isFavorite {
            annotations[address] = nil
        } else {
            annotations[address] = annotation
        }
        if let index = resultIndices[address] {
            results[index].comment = annotation.comment.isEmpty ? nil : annotation.comment
        }
        do {
            try NetToysScannerStore.saveAnnotations(annotations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyScanUpdate(_ update: NetToysScanResult) {
        var update = update
        if let comment = annotations[update.id]?.comment, !comment.isEmpty {
            update.comment = comment
        }
        if let index = resultIndices[update.id] {
            results[index] = update
        } else {
            resultIndices[update.id] = results.endIndex
            results.append(update)
        }
    }

    private func replaceResults(_ values: [NetToysScanResult]) {
        results = values
        rebuildResultIndices()
        for index in results.indices {
            if let comment = annotations[results[index].id]?.comment, !comment.isEmpty {
                results[index].comment = comment
            }
        }
    }

    private func rebuildResultIndices() {
        resultIndices = Dictionary(uniqueKeysWithValues: results.indices.map { (results[$0].id, $0) })
    }

}

nonisolated struct NetToysScannerPreferences: Codable, Equatable, Sendable {
    let portInput: String
    let timeoutMilliseconds: Int
    let concurrency: Int
    let launchDelayMilliseconds: Int
    let collectPingDetails: Bool
    let pingProbeCount: Int
    let detectHTTPServer: Bool
    let detectHTTPProxy: Bool
    let detectNetBIOS: Bool
    let customTextEnabled: Bool
    let customTextPort: Int
    let customTextRequest: String
    let customTextPattern: String
}

nonisolated struct NetToysLivenessPreferences: Codable, Equatable, Sendable {
    let method: NetToysLivenessMethod
    let pingTimeoutMilliseconds: Int
    let adaptiveTCPTimeout: Bool
    let scanUnresponsiveHosts: Bool
}

struct NetToysScannerView: View {
    @Bindable var model: NetToysScannerViewModel
    @AppStorage("nettoys.scanner.table-columns")
    private var columnCustomization: TableColumnCustomization<NetToysScanResult>
    let openSettings: () -> Void
    @State private var searchFocus = 0
    @State private var pendingRemoval = Set<String>()
    @State private var confirmRemoval = false
    @State private var networkSubtitle = "No active network"
    @State private var showRandomTargets = false
    @State private var showStatistics = false
    @State private var detailResult: NetToysScanResult?
    @State private var openerPreview: NetToysOpenerPreview?
    @State private var neighborService = NetToysNeighborServiceManager.shared

    private var macAccessEnabled: Bool {
        _ = neighborService.revision
        return neighborService.isEnabled
    }

    private var sortedResults: [NetToysScanResult] {
        model.visibleResults.sorted(using: model.sortOrder)
    }

    private var selectedRows: [NetToysScanResult] {
        model.results.filter { model.selection.contains($0.id) }
    }

    init(model: NetToysScannerViewModel, openSettings: @escaping () -> Void = {}) {
        self.model = model
        self.openSettings = openSettings
    }

    var body: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "IP Scanner", subtitle: networkSubtitle) {
                OnePlusStatus("MAC access: \(macAccessTitle)", state: macAccessEnabled ? .online : .warning)
                Button(action: openSettings) {
                    Label("Scanner Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(OnePlusButtonStyle(.ghost))
            }
        } content: {
            OnePlusCard { scanControls.padding(OnePlusMetrics.cardPadding) }
            if !macAccessEnabled {
                OnePlusBanner(neighborService.errorMessage ?? "Allow MAC access to identify neighboring devices.", tone: .warning) {
                    Button(neighborService.status == .requiresApproval ? "Open Login Items" : "Enable MAC Access") {
                        neighborService.enable()
                    }
                }
            }
            resultControls
            OnePlusCard {
                resultsTable.frame(maxHeight: .infinity)
                OnePlusRule()
                statusBar
            }.frame(maxHeight: .infinity)
        }
        .sheet(isPresented: $showRandomTargets) {
            NetToysRandomTargetsView(model: model)
        }
        .sheet(isPresented: $showStatistics) {
            NetToysStatisticsView(statistics: NetToysScanStatistics(
                results: model.results,
                duration: model.lastDuration
            ))
        }
        .sheet(item: $detailResult) { result in
            NetToysHostDetailsView(model: model, result: result)
        }
        .sheet(item: $openerPreview) { preview in
            NetToysOpenerPreviewSheet(preview: preview)
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysStartScan)) { notification in
            guard let run = notification.object as? NetToysScanRun else { return }
            model.targetInput = run.target
            model.portInput = run.ports.map(String.init).joined(separator: ", ")
            model.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysPrefill)) { notification in
            applyPrefill(DeepLinkHandler.shared.takeNetToysPrefill()
                ?? notification.object as? NetToysScanPrefill)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            neighborService.refresh()
            refreshNetworkSubtitle()
        }
        .onAppear {
            applyPrefill(DeepLinkHandler.shared.takeNetToysPrefill())
            refreshNetworkSubtitle()
        }
        .background { Button("Find results") { searchFocus += 1 }.keyboardShortcut("f").hidden() }
        .confirmationDialog("Remove selected results?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove Results", role: .destructive) {
                model.removeResults(ids: pendingRemoval)
                model.selection.subtract(pendingRemoval)
                pendingRemoval.removeAll()
            }
            Button("Cancel", role: .cancel) { pendingRemoval.removeAll() }
        }
        .alert("IP Scanner", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var scanControls: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusTextField("Address, range, CIDR, or list", text: $model.targetInput)
                .accessibilityLabel("Scan targets")
            OnePlusTextField("Ports", text: $model.portInput)
                .frame(width: OnePlusMetrics.controlColumn)
                .accessibilityLabel("TCP ports")
            OnePlusActionMenu(model.isImporting ? "Importing..." : "Presets") {
                Button("Use Local Subnet") {
                    if let network = LocalIPv4Network.active() { model.targetInput = network.cidr }
                }
                Button("Random Addresses…") { showRandomTargets = true }
                Button("Import Target List…") { model.importTargets() }
                    .disabled(model.isScanning || model.isImporting)
                Button("Load Saved Results…") { model.loadResults() }
                    .disabled(model.isScanning || model.isImporting)
                Divider()
                Button(model.favoriteTargets.contains(model.targetInput)
                    ? "Remove Current Favorite"
                    : "Save Current Favorite") {
                    model.toggleFavoriteTarget()
                }
                if !model.favoriteTargets.isEmpty {
                    Menu("Favorite Targets") {
                        ForEach(model.favoriteTargets, id: \.self) { target in
                            Button(target) { model.targetInput = target }
                        }
                    }
                }
            }
            .accessibilityLabel(model.isImporting ? "Importing scan file" : "More scan options")

            if model.isScanning {
                Button("Stop", role: .cancel) { model.cancel() }
            } else {
                Button("Scan") { model.start() }
                    .buttonStyle(OnePlusButtonStyle(.primary))
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.isImporting)
            }
        }
    }

    private func applyPrefill(_ prefill: NetToysScanPrefill?) {
        guard let prefill else { return }
        model.targetInput = prefill.targets
        if let ports = prefill.ports { model.portInput = ports }
    }

    private var resultControls: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusSegmented(choices: [
                (.all, "All \(model.results.count)"),
                (.alive, "Alive \(model.results.filter(\.isReachable).count)"),
                (.openPorts, "Open Ports \(model.results.filter { !$0.openPorts.isEmpty }.count)")
            ], selection: $model.filter, accessibilityLabel: "Results")
                .fixedSize()
            OnePlusSearchField(prompt: "Find address, host, MAC, or port", text: $model.searchText,
                               width: nil, focusTrigger: searchFocus)

            Spacer()

            OnePlusActionMenu("More", width: OnePlusMetrics.controlColumn / 2) {
                Menu("Go to Result") {
                    Button("Next Alive Host") { select(offset: 1, where: \.isReachable) }
                    Button("Previous Alive Host") { select(offset: -1, where: \.isReachable) }
                    Divider()
                    Button("Next Down Host") { select(offset: 1) { !$0.isReachable } }
                    Button("Previous Down Host") { select(offset: -1) { !$0.isReachable } }
                    Divider()
                    Button("Next Host With Open Ports") { select(offset: 1) { !$0.openPorts.isEmpty } }
                    Button("Previous Host With Open Ports") { select(offset: -1) { !$0.openPorts.isEmpty } }
                }
                Button("Scan Statistics…") { showStatistics = true }
                    .disabled(model.results.isEmpty)
                Button("Add SSH Anchor") {
                    if let result = selectedRows.first { openSSHAnchor(result) }
                }
                .disabled(selectedRows.count != 1)
                Divider()
                Button("Copy Selected Details") { copyDetails(selectedRows) }
                    .disabled(model.selection.isEmpty)
                Button("Delete Selected", role: .destructive) {
                    pendingRemoval = model.selection
                    confirmRemoval = true
                }
                .disabled(model.selection.isEmpty)
            }

            Button("Copy IP") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selectedRows.map { $0.address.description }.joined(separator: "\n"), forType: .string)
            }
            .disabled(model.selection.isEmpty)

            Button("Rescan") {
                model.start(targets: selectedRows.map(\.address))
            }
            .disabled(model.selection.isEmpty || model.isScanning)

            OnePlusActionMenu("Export", width: OnePlusMetrics.controlColumn / 2) {
                ForEach(NetToysExportFormat.allCases) { format in
                    Button(format.rawValue) {
                        model.export(format, rows: selectedRows.isEmpty ? sortedResults : selectedRows)
                    }
                }
                Divider()
                Menu("Append to Existing File") {
                    ForEach(NetToysExportFormat.allCases.filter(\.canAppend)) { format in
                        Button(format.rawValue) {
                            model.append(format, rows: selectedRows.isEmpty ? sortedResults : selectedRows)
                        }
                    }
                }
            }
            .disabled(sortedResults.isEmpty || model.isExporting)
            if model.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Exporting scan results")
            }
        }
    }

    private var resultsTable: some View {
        Table(
            sortedResults,
            selection: $model.selection,
            sortOrder: $model.sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("IP Address", value: \.sortAddress) { result in
                Text(result.address.description)
                    .onePlusText(.mono)
                    .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
            }
            .width(min: 112, ideal: 126)
            .customizationID("nettoys.ip")
            .disabledCustomizationBehavior(.visibility)

            Group {
                TableColumn("Status", value: \NetToysScanResult.statusTitle) { result in
                    OnePlusStatus(result.statusTitle, state: result.isReachable ? .online : .offline)
                }
                .width(min: 68, ideal: 76)
                .customizationID("nettoys.status")

                TableColumn("Response", value: \NetToysScanResult.responseTitle) { result in
                    Text(result.responseTitle.isEmpty ? "—" : "\(result.responseTitle) ms")
                        .onePlusText(.mono)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 76, ideal: 86)
                .customizationID("nettoys.response")

                TableColumn("TTL", value: \NetToysScanResult.ttlTitle) { result in
                    Text(result.ttlTitle.isEmpty ? "—" : result.ttlTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 44, ideal: 48)
                .customizationID("nettoys.ttl")
                .defaultVisibility(.hidden)

                TableColumn("Loss", value: \NetToysScanResult.packetLossTitle) { result in
                    Text(result.packetLossTitle.isEmpty ? "—" : "\(result.packetLossTitle)%")
                        .monospacedDigit()
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 58, ideal: 66)
                .customizationID("nettoys.loss")
                .defaultVisibility(.hidden)
            }

            Group {
                TableColumn("Hostname", value: \NetToysScanResult.hostnameTitle) { result in
                    Text(result.hostnameTitle.isEmpty ? "—" : result.hostnameTitle)
                        .lineLimit(1).help(result.hostnameTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 116, ideal: 154)
                .customizationID("nettoys.hostname")

                TableColumn("MAC Address", value: \NetToysScanResult.macTitle) { result in
                    Text(result.macTitle.isEmpty ? "—" : result.macTitle)
                        .onePlusText(.mono)
                        .help(result.macHelp)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 130, ideal: 142)
                .customizationID("nettoys.mac")

                TableColumn("MAC Vendor", value: \NetToysScanResult.vendorTitle) { result in
                    Text(result.vendorTitle.isEmpty ? "—" : result.vendorTitle)
                        .lineLimit(1).help(result.vendorTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 120, ideal: 160)
                .customizationID("nettoys.vendor")

                TableColumn("NetBIOS Info", value: \NetToysScanResult.netBIOSTitle) { result in
                    Text(result.netBIOSTitle.isEmpty ? "—" : result.netBIOSTitle)
                        .lineLimit(1).help(result.netBIOSTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 90, ideal: 120)
                .customizationID("nettoys.netbios")
                .defaultVisibility(.hidden)
            }

            Group {
                TableColumn("Open Ports", value: \NetToysScanResult.portsTitle) { result in
                    Text(result.portsTitle.isEmpty ? "—" : result.portsTitle)
                        .lineLimit(1).help(result.portsTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 86, ideal: 106)
                .customizationID("nettoys.open-ports")

                TableColumn("Filtered", value: \NetToysScanResult.filteredPortsTitle) { result in
                    Text(result.filteredPortsTitle.isEmpty ? "—" : result.filteredPortsTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 80, ideal: 100)
                .customizationID("nettoys.filtered-ports")
                .defaultVisibility(.hidden)

                TableColumn("HTTP Server", value: \NetToysScanResult.httpServerTitle) { result in
                    Text(result.httpServerTitle.isEmpty ? "—" : result.httpServerTitle)
                        .lineLimit(1).help(result.httpServerTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 110, ideal: 150)
                .customizationID("nettoys.http-server")
                .defaultVisibility(.hidden)

                TableColumn("HTTP Proxy", value: \NetToysScanResult.httpProxyTitle) { result in
                    Text(result.httpProxyTitle.isEmpty ? "—" : result.httpProxyTitle)
                        .lineLimit(1).help(result.httpProxyTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 100, ideal: 140)
                .customizationID("nettoys.http-proxy")
                .defaultVisibility(.hidden)

                TableColumn("Custom Text", value: \NetToysScanResult.customTextTitle) { result in
                    Text(result.customTextTitle.isEmpty ? "—" : result.customTextTitle)
                        .lineLimit(1).help(result.customTextTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 110, ideal: 160)
                .customizationID("nettoys.custom-text")
                .defaultVisibility(.hidden)

                TableColumn("Comments", value: \NetToysScanResult.commentTitle) { result in
                    Text(result.commentTitle.isEmpty ? "—" : result.commentTitle)
                        .lineLimit(1).help(result.commentTitle)
                        .foregroundStyle(result.isReachable ? OnePlusColor.ink : OnePlusColor.muted)
                }
                .width(min: 100, ideal: 150)
                .customizationID("nettoys.comments")
                .defaultVisibility(.hidden)
            }
        }
        .contextMenu(forSelectionType: String.self) { selected in
            if let result = model.results.first(where: { selected.contains($0.id) }) {
                Button("Details and Comment…") { detailResult = result }
                Button(model.annotation(for: result.id).isFavorite ? "Remove Host Favorite" : "Favorite Host") {
                    var annotation = model.annotation(for: result.id)
                    annotation.isFavorite.toggle()
                    model.saveAnnotation(annotation, for: result.id)
                }
                Button("Add SSH Anchor") { openSSHAnchor(result) }
                if let opener = (model.openers + NetToysOpener.defaults).first(where: { $0.applies(to: result) && $0.urlTemplate.hasPrefix("http") }) {
                    Button("Open in Browser") { preview(opener, result: result) }
                }
                if let opener = (model.openers + NetToysOpener.defaults).first(where: { $0.applies(to: result) && $0.urlTemplate.hasPrefix("ssh:") }) {
                    Button("SSH") { preview(opener, result: result) }
                }
                Divider()
                let openers = model.openers.filter { $0.applies(to: result) }
                if !openers.isEmpty {
                    Menu("Open With") {
                        ForEach(openers) { opener in
                            Button(opener.name) { preview(opener, result: result) }
                        }
                    }
                }
                Divider()
            }
            Button("Copy IP Address") {
                let rows = model.results.filter { selected.contains($0.id) }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rows.map { $0.address.description }.joined(separator: "\n"), forType: .string)
            }
            Button("Copy Row") {
                copyDetails(model.results.filter { selected.contains($0.id) })
            }
            Button("Rescan Host") {
                model.start(targets: model.results.filter { selected.contains($0.id) }.map(\.address))
            }
            .disabled(model.isScanning)
            Button("Delete", role: .destructive) {
                pendingRemoval = selected
                confirmRemoval = true
            }
        } primaryAction: { selected in
            detailResult = model.results.first { selected.contains($0.id) }
        }
        .onePlusNativeTable()
        .overlay {
            if sortedResults.isEmpty && !model.isScanning {
                OnePlusEmptyState(model.results.isEmpty ? "Ready to scan" : "No matching hosts",
                                  systemImage: "network", caption: model.results.isEmpty
                                  ? "Enter targets and ports, then press Return to scan."
                                  : "Change the filter or search to show more results.")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            if model.isScanning {
                ProgressView(value: Double(model.completed), total: Double(max(model.total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("\(model.completed) of \(model.total)")
                    .monospacedDigit()
                Text("·")
                Text("\(sortedResults.count) shown")
                Text("·")
                Text("\(model.results.filter(\.isReachable).count) alive")
            } else {
                Text("\(sortedResults.count) shown")
                Text("·")
                Text("\(model.results.filter(\.isReachable).count) alive")
                Text("·")
                Text("\(model.results.filter { !$0.openPorts.isEmpty }.count) with open ports")
            }
            Spacer()
            if let duration = model.lastDuration {
                Text("Completed in \(duration.formatted(.number.precision(.fractionLength(1)))) s")
            }
        }
        .onePlusText(.caption)
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.cardHeader)
    }

    private var macAccessTitle: String {
        _ = neighborService.revision
        return switch neighborService.status {
        case .enabled: "Allowed"
        case .requiresApproval: "Needs Approval"
        case .notRegistered: "Not Enabled"
        default: "Unavailable"
        }
    }

    private func refreshNetworkSubtitle() {
        guard let network = LocalIPv4Network.active() else { networkSubtitle = "No active network"; return }
        let status = NetToysConfigurationStore.status()
        let identity = status?.network.map { NetworkIdentity(networkID: $0.networkID, ssid: $0.ssid) }
        let ssid = status?.ssidAccess == .allowed && identity?.interfaceName == network.interfaceName ? identity?.ssid : nil
        networkSubtitle = [network.interfaceName, ssid, network.cidr].compactMap { $0 }.joined(separator: " · ")
    }

    private func preview(_ opener: NetToysOpener, result: NetToysScanResult) {
        do {
            openerPreview = NetToysOpenerPreview(
                name: opener.name,
                url: try opener.resolvedURL(address: result.address, hostname: result.hostname)
            )
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func copyDetails(_ rows: [NetToysScanResult]) {
        guard !rows.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NetToysScanExport.text(rows), forType: .string)
    }

    private func openSSHAnchor(_ result: NetToysScanResult) {
        NotificationCenter.default.post(
            name: .netToysOpenAnchor,
            object: NetToysAnchorPrefill(
                address: result.address.description,
                macAddress: result.macAddress,
                hostname: result.hostname
            )
        )
    }

    private func select(offset: Int, where predicate: (NetToysScanResult) -> Bool) {
        let matches = sortedResults.filter(predicate)
        guard !matches.isEmpty else { return }
        let current = model.selection.first.flatMap { id in matches.firstIndex { $0.id == id } }
        let index = current.map { ($0 + offset + matches.count) % matches.count }
            ?? (offset < 0 ? matches.count - 1 : 0)
        let next = matches[index]
        model.selection = [next.id]
    }
}

private struct NetToysStatisticsView: View {
    let statistics: NetToysScanStatistics
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OnePlusSheet("Scan statistics", close: { dismiss() }) {
            OnePlusCard {
                VStack(spacing: 0) {
                row("Addresses", statistics.addressCount.formatted())
                row("Reachable", statistics.reachableCount.formatted())
                row("Down", statistics.downCount.formatted())
                row("Hosts with open ports", statistics.openPortHostCount.formatted())
                row("Open ports", statistics.openPortCount.formatted())
                row("Average response", milliseconds(statistics.averageResponseMilliseconds))
                row("Fastest response", milliseconds(statistics.fastestResponseMilliseconds))
                row("Slowest response", milliseconds(statistics.slowestResponseMilliseconds))
                row("Duration", statistics.duration.map { "\($0.formatted(.number.precision(.fractionLength(1)))) s" } ?? "Not available")
                row("Scan rate", statistics.addressesPerSecond.map { "\($0.formatted(.number.precision(.fractionLength(1)))) addresses/s" } ?? "Not available")
                }.padding(OnePlusMetrics.cardPadding)
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        OnePlusKeyValueRow(label, value: value, monospaced: true)
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(1)))) ms" } ?? "Not available"
    }
}

struct NetToysScannerSettingsView: View {
    @Bindable var model: NetToysScannerViewModel
    @State private var errorMessage: String?
    @State private var openers: [NetToysOpener]
    @State private var pendingOpenerRemoval: UUID?
    @State private var confirmRestore = false

    init(model: NetToysScannerViewModel) {
        self.model = model
        _openers = State(initialValue: model.openers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    settingsSection("Scan Engine") {
                        stepper("TCP timeout", value: $model.timeoutMilliseconds, range: 100...5_000, step: 100, unit: "ms")
                        stepper("Parallel connections", value: $model.concurrency, range: 1...256)
                        stepper("Launch delay", value: $model.launchDelayMilliseconds, range: 0...100, step: 5, unit: "ms")
                    }

                    settingsSection("Host Detection") {
                        OnePlusSettingRow("Liveness", controlWidth: OnePlusMetrics.wideControlColumn) {
                            OnePlusSelect(choices: NetToysLivenessMethod.allCases.map { ($0, $0.rawValue) },
                                          selection: $model.livenessMethod, width: OnePlusMetrics.wideControlColumn,
                                          accessibilityLabel: "Liveness")
                        }
                        settingsToggle("Use response-based TCP timeout", isOn: $model.adaptiveTCPTimeout)
                        if model.livenessMethod == .icmpAndTCP {
                            settingsToggle("Scan hosts that do not answer ICMP", isOn: $model.scanUnresponsiveHosts)
                        }
                        settingsToggle("Collect ICMP TTL and packet loss", isOn: $model.collectPingDetails)
                        if model.collectPingDetails || model.livenessMethod == .icmpAndTCP || model.adaptiveTCPTimeout {
                            stepper("ICMP timeout", value: $model.pingTimeoutMilliseconds, range: 100...5_000, step: 100, unit: "ms")
                            stepper("ICMP probes", value: $model.pingProbeCount, range: 1...5)
                        }
                    }

                    settingsSection("Protocol Fetchers") {
                        settingsToggle("Detect HTTP servers", isOn: $model.detectHTTPServer)
                        settingsToggle("Detect HTTP proxies", isOn: $model.detectHTTPProxy)
                        settingsToggle("Read NetBIOS names", isOn: $model.detectNetBIOS)
                        settingsToggle("Use custom text probe", isOn: $model.customTextEnabled)
                        if model.customTextEnabled {
                            stepper("Custom port", value: $model.customTextPort, range: 1...65_535)
                            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                                Text("Request").onePlusText(.row).frame(maxWidth: .infinity, alignment: .leading)
                                OnePlusTextEditor("Request", text: $model.customTextRequest)
                                    .frame(width: OnePlusMetrics.controlColumn * 3, height: OnePlusMetrics.controlHeight * 3)
                            }.padding(OnePlusMetrics.cardPadding)
                            OnePlusSettingRow("Response regular expression", controlWidth: OnePlusMetrics.controlColumn * 3) {
                                OnePlusTextField("Response regular expression", text: $model.customTextPattern)
                            }
                        }
                    }

                    settingsSection("MAC Addresses") {
                        Text("Allow MAC access in Permissions, then rescan devices with missing addresses.")
                            .onePlusText(.row).padding(OnePlusMetrics.cardPadding)
                    }

                    settingsSection("Openers") {
                        Grid(alignment: .leading, horizontalSpacing: OnePlusMetrics.actionSpacing,
                             verticalSpacing: OnePlusMetrics.actionSpacing) {
                            GridRow {
                                Text("Name")
                                Text("URL template")
                                Text("Port")
                                Color.clear.frame(width: OnePlusMetrics.controlHeight)
                            }
                            .onePlusText(.tableHeader)

                            ForEach($openers) { $opener in
                                GridRow {
                                    OnePlusTextField("Name", text: $opener.name)
                                        .frame(width: OnePlusMetrics.controlColumn)
                                    OnePlusTextField("URL template", text: $opener.urlTemplate)
                                    OnePlusStepperField("Port", value: $opener.requiredPort,
                                                        in: 1...65_535).frame(width: OnePlusMetrics.controlColumn)
                                    Button(role: .destructive) {
                                        pendingOpenerRemoval = opener.id
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(OnePlusButtonStyle(.icon))
                                    .help("Delete \(opener.name) opener")
                                    .accessibilityLabel("Delete \(opener.name) opener")
                                }
                            }
                        }
                        .padding(OnePlusMetrics.cardPadding)

                        HStack {
                            Button("Add Opener") {
                                guard openers.count < 20 else { return }
                                openers.append(NetToysOpener(
                                    name: "New Opener",
                                    urlTemplate: "http://{ip}:{port}/",
                                    requiredPort: 80
                                ))
                            }
                            Button("Restore Defaults") { confirmRestore = true }
                        }
                        .padding(.horizontal, OnePlusMetrics.cardPadding)
                        Text("Use {ip}, {hostname}, and {port}. NetToys opens only URL protocols and always shows a preview.")
                            .onePlusText(.caption).padding(OnePlusMetrics.cardPadding)
                    }
            if let errorMessage { OnePlusBanner(errorMessage, tone: .error) }
        }
        .onDisappear { model.savePreferences() }
        .onChange(of: openers) { saveOpeners() }
        .onChange(of: model.livenessMethod) { model.savePreferences() }
        .onChange(of: model.customTextRequest) { model.savePreferences() }
        .onChange(of: model.customTextPattern) { model.savePreferences() }
        .confirmationDialog("Remove this opener?", isPresented: Binding(
            get: { pendingOpenerRemoval != nil }, set: { if !$0 { pendingOpenerRemoval = nil } }
        )) {
            Button("Remove opener", role: .destructive) {
                openers.removeAll { $0.id == pendingOpenerRemoval }
                pendingOpenerRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingOpenerRemoval = nil }
        }
        .confirmationDialog("Restore default openers?", isPresented: $confirmRestore) {
            Button("Restore defaults", role: .destructive) { openers = NetToysOpener.defaults }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This replaces your current opener list.") }
    }

    private func saveOpeners() {
        do {
            try model.saveOpeners(openers)
            model.savePreferences()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        OnePlusCard {
            OnePlusCardHeader(title)
            content()
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        OnePlusSettingRow(title) {
            Toggle(title, isOn: Binding(get: { isOn.wrappedValue }, set: {
                isOn.wrappedValue = $0
                model.savePreferences()
            })).labelsHidden().toggleStyle(OnePlusSwitchStyle())
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>,
                         step: Int = 1, unit: String? = nil) -> some View {
        OnePlusSettingRow(title) {
            OnePlusStepperField(title, value: Binding(get: { value.wrappedValue }, set: {
                value.wrappedValue = $0
                model.savePreferences()
            }), in: range, step: step, unit: unit)
        }
    }
}

private struct NetToysOpenerPreview: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

private struct NetToysOpenerPreviewSheet: View {
    let preview: NetToysOpenerPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OnePlusSheet("Open with \(preview.name)?", close: { dismiss() }) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            Text("Review the complete URL before another app opens it.")
                .onePlusText(.row).foregroundStyle(OnePlusColor.secondary)
            OnePlusCard {
            Text(preview.url.absoluteString)
                .onePlusText(.mono)
                .textSelection(.enabled)
                .padding(OnePlusMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        } footer: {
                Button("Cancel") { dismiss() }.buttonStyle(OnePlusButtonStyle(.ghost))
                Button("Open") {
                    NSWorkspace.shared.open(preview.url)
                    dismiss()
                }
                .buttonStyle(OnePlusButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct NetToysRandomTargetsView: View {
    @Bindable var model: NetToysScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cidr = LocalIPv4Network.active()?.cidr ?? "192.168.1.0/24"
    @State private var count = 32

    var body: some View {
        OnePlusSheet("Random targets", close: { dismiss() }) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            Text("Generate unique usable IPv4 addresses inside one CIDR block.")
                .onePlusText(.row).foregroundStyle(OnePlusColor.secondary)
            OnePlusCard {
                OnePlusSettingRow("CIDR", controlWidth: OnePlusMetrics.wideControlColumn) {
                    OnePlusTextField("CIDR", text: $cidr)
                }
                OnePlusSettingRow("Address count") {
                    OnePlusStepperField("Address count", value: $count, in: 1...1_024)
                }
            }
            }
        } footer: {
                Button("Cancel") { dismiss() }.buttonStyle(OnePlusButtonStyle(.ghost))
                Button("Generate") {
                    model.generateRandomTargets(cidr: cidr, count: count)
                    dismiss()
                }
                .buttonStyle(OnePlusButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct NetToysHostDetailsView: View {
    let model: NetToysScannerViewModel
    let result: NetToysScanResult
    @Environment(\.dismiss) private var dismiss
    @State private var annotation: NetToysHostAnnotation

    init(model: NetToysScannerViewModel, result: NetToysScanResult) {
        self.model = model
        self.result = result
        _annotation = State(initialValue: model.annotation(for: result.id))
    }

    var body: some View {
        OnePlusSheet(result.address.description, close: { dismiss() }) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                HStack {
                    Text(result.hostnameTitle.isEmpty ? "No reverse hostname" : result.hostnameTitle)
                        .onePlusText(.row).foregroundStyle(OnePlusColor.secondary)
                Spacer()
                Toggle("Favorite", isOn: $annotation.isFavorite)
                    .toggleStyle(OnePlusSwitchStyle()).fixedSize()
            }

            ScrollView {
            OnePlusCard {
                VStack(spacing: 0) {
                detailRow("Status", result.statusTitle)
                detailRow("Response", result.responseTitle.isEmpty ? "Not available" : "\(result.responseTitle) ms")
                detailRow("TTL", result.ttlTitle.isEmpty ? "Not collected" : result.ttlTitle)
                detailRow("Packet loss", result.packetLossTitle.isEmpty ? "Not collected" : "\(result.packetLossTitle)%")
                detailRow("MAC address", result.macTitle.isEmpty ? "Not available" : result.macTitle)
                detailRow("MAC vendor", result.vendor ?? "Not available")
                detailRow("Open ports", result.portsTitle.isEmpty ? "None" : result.portsTitle)
                detailRow("Filtered ports", result.filteredPortsTitle.isEmpty ? "None" : result.filteredPortsTitle)
                detailRow("HTTP server", result.httpServerTitle.isEmpty ? "Not detected" : result.httpServerTitle)
                detailRow("HTTP proxy", result.httpProxyTitle.isEmpty ? "Not detected" : result.httpProxyTitle)
                detailRow("NetBIOS name", result.netBIOSTitle.isEmpty ? "Not detected" : result.netBIOSTitle)
                detailRow("Custom text", result.customTextTitle.isEmpty ? "No match" : result.customTextTitle)
                }.padding(OnePlusMetrics.cardPadding)
            }.frame(maxWidth: .infinity)
            }.frame(maxHeight: OnePlusMetrics.captionedSettingRow * 6).onePlusScrollIndicators()
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                Text("Comment").onePlusText(.cardTitle)
                OnePlusTextEditor("Host comment", text: $annotation.comment)
                    .frame(height: OnePlusMetrics.controlHeight * 3)
                    .accessibilityLabel("Host comment")
            }
            }
        } footer: {
                Button("Cancel") { dismiss() }.buttonStyle(OnePlusButtonStyle(.ghost))
                Button("Save") {
                    model.saveAnnotation(annotation, for: result.id)
                    dismiss()
                }
                .buttonStyle(OnePlusButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        OnePlusKeyValueRow(label, value: value)
    }
}
