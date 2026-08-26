import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum NetToysResultFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case alive = "Alive"
    case openPorts = "Open Ports"

    var id: String { rawValue }
}

enum NetToysExportFormat: String, CaseIterable, Identifiable {
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
            ? "macOS restricts neighboring device MAC addresses to Apple-entitled processes."
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
    var sortOrder = [KeyPathComparator(\NetToysScanResult.sortAddress)]

    private let defaults: UserDefaults
    private let scanner = NetToysScanner()
    private var scanTask: Task<Void, Never>?

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
                result.netBIOSTitle, result.customTextTitle
            ]
                + [annotations[result.id]?.comment ?? ""])
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func start(targets override: [IPv4Address]? = nil) {
        guard !isScanning else { return }
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
                        fetchOptions: fetchOptions
                    ) { completed, total in
                        Task { @MainActor in
                            self.completed = completed
                            self.total = total
                        }
                    }
                    guard !Task.isCancelled else { return }
                    let duration = Date().timeIntervalSince(started)
                    results = values
                    lastDuration = duration
                    isScanning = false
                    scanTask = nil
                    try NetToysScannerStore.record(NetToysScanRun(
                        target: sourceTarget,
                        ports: Set(targets.flatMap(\.ports)).sorted(),
                        duration: duration,
                        results: values
                    ))
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                    isScanning = false
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
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func importTargets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let targets = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let value = line.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        targetInput = targets.joined(separator: ", ")
    }

    func export(_ format: NetToysExportFormat, rows: [NetToysScanResult]) {
        guard !rows.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetToys Scan.\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func append(_ format: NetToysExportFormat, rows: [NetToysScanResult]) {
        guard format.canAppend, !rows.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Append"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let isEmpty = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == 0
            let value = switch format {
            case .csv: NetToysScanExport.csv(rows, includeHeader: isEmpty)
            case .text: NetToysScanExport.text(rows)
            case .ipPorts: NetToysScanExport.ipPorts(rows)
            case .sql: NetToysScanExport.sql(rows, includeSchema: isEmpty)
            case .savedResults, .xml: ""
            }
            try NetToysScanExport.append(value, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadResults() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "nettoys") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            results = try NetToysScanImport.savedResults(Data(contentsOf: url))
            lastDuration = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeResults(ids: Set<String>) {
        results.removeAll { ids.contains($0.id) }
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
        do {
            try NetToysScannerStore.saveAnnotations(annotations)
        } catch {
            errorMessage = error.localizedDescription
        }
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
    @State private var showSettings = false
    @State private var showRandomTargets = false
    @State private var showStatistics = false
    @State private var detailResult: NetToysScanResult?
    @State private var openerPreview: NetToysOpenerPreview?

    private var sortedResults: [NetToysScanResult] {
        model.visibleResults.sorted(using: model.sortOrder)
    }

    private var selectedRows: [NetToysScanResult] {
        model.results.filter { model.selection.contains($0.id) }
    }

    init(model: NetToysScannerViewModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "IP Scanner", subtitle: scanSubtitle) {
                Button {
                    showSettings = true
                } label: {
                    Label("Scanner Settings", systemImage: "slider.horizontal.3")
                }
            }

            scanControls
            QuietDivider()
            resultControls
            QuietDivider()
            resultsTable
            QuietDivider()
            statusBar
        }
        .sheet(isPresented: $showSettings) {
            NetToysScannerSettingsView(model: model)
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
        .onAppear {
            applyPrefill(DeepLinkHandler.shared.takeNetToysPrefill())
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
        HStack(spacing: 8) {
            TextField("Address, range, CIDR, or list", text: $model.targetInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Scan targets")

            TextField("Ports", text: $model.portInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .accessibilityLabel("TCP ports")

            Menu {
                Button("Use Local Subnet") {
                    if let network = LocalIPv4Network.active() { model.targetInput = network.cidr }
                }
                Button("Random Addresses…") { showRandomTargets = true }
                Button("Import Target List…") { model.importTargets() }
                Button("Load Saved Results…") { model.loadResults() }
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
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if model.isScanning {
                Button("Stop", role: .cancel) { model.cancel() }
            } else {
                Button("Scan") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .controlSize(.small)
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .padding(.vertical, 10)
    }

    private func applyPrefill(_ prefill: NetToysScanPrefill?) {
        guard let prefill else { return }
        model.targetInput = prefill.targets
        if let ports = prefill.ports { model.portInput = ports }
    }

    private var resultControls: some View {
        HStack(spacing: 10) {
            Picker("Results", selection: $model.filter) {
                ForEach(NetToysResultFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)

            NativeSearchField(text: $model.searchText, placeholder: "Find address, host, MAC, or port")
                .frame(maxWidth: 320)
                .frame(height: UtilityLayout.workspaceActionHeight)

            Spacer()

            Menu("More") {
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
                    model.removeResults(ids: model.selection)
                    model.selection.removeAll()
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

            Menu("Export") {
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
            .disabled(sortedResults.isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .padding(.vertical, 8)
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
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 112, ideal: 126)
            .customizationID("nettoys.ip")
            .disabledCustomizationBehavior(.visibility)

            Group {
                TableColumn("Status", value: \NetToysScanResult.statusTitle) { result in
                    Label(result.statusTitle, systemImage: result.isReachable ? "circle.fill" : "circle")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(result.isReachable ? .green : .secondary)
                }
                .width(min: 68, ideal: 76)
                .customizationID("nettoys.status")

                TableColumn("Response", value: \NetToysScanResult.responseTitle) { result in
                    Text(result.responseTitle.isEmpty ? "—" : "\(result.responseTitle) ms")
                        .monospacedDigit()
                }
                .width(min: 76, ideal: 86)
                .customizationID("nettoys.response")

                TableColumn("TTL", value: \NetToysScanResult.ttlTitle) { result in
                    Text(result.ttlTitle.isEmpty ? "—" : result.ttlTitle)
                }
                .width(min: 44, ideal: 48)
                .customizationID("nettoys.ttl")
                .defaultVisibility(.hidden)

                TableColumn("Loss", value: \NetToysScanResult.packetLossTitle) { result in
                    Text(result.packetLossTitle.isEmpty ? "—" : "\(result.packetLossTitle)%")
                        .monospacedDigit()
                }
                .width(min: 58, ideal: 66)
                .customizationID("nettoys.loss")
                .defaultVisibility(.hidden)
            }

            Group {
                TableColumn("Hostname", value: \NetToysScanResult.hostnameTitle) { result in
                    Text(result.hostnameTitle.isEmpty ? "—" : result.hostnameTitle)
                        .lineLimit(1)
                }
                .width(min: 116, ideal: 154)
                .customizationID("nettoys.hostname")

                TableColumn("MAC Address", value: \NetToysScanResult.macTitle) { result in
                    Text(result.macTitle.isEmpty ? "—" : result.macTitle)
                        .font(.system(.body, design: .monospaced))
                        .help(result.macHelp)
                }
                .width(min: 130, ideal: 142)
                .customizationID("nettoys.mac")

                TableColumn("MAC Vendor", value: \NetToysScanResult.vendorTitle) { result in
                    Text(result.vendorTitle.isEmpty ? "—" : result.vendorTitle)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 160)
                .customizationID("nettoys.vendor")
                .defaultVisibility(.hidden)

                TableColumn("NetBIOS", value: \NetToysScanResult.netBIOSTitle) { result in
                    Text(result.netBIOSTitle.isEmpty ? "—" : result.netBIOSTitle)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 120)
                .customizationID("nettoys.netbios")
                .defaultVisibility(.hidden)
            }

            Group {
                TableColumn("Open Ports", value: \NetToysScanResult.portsTitle) { result in
                    Text(result.portsTitle.isEmpty ? "—" : result.portsTitle)
                }
                .width(min: 86, ideal: 106)
                .customizationID("nettoys.open-ports")

                TableColumn("Filtered", value: \NetToysScanResult.filteredPortsTitle) { result in
                    Text(result.filteredPortsTitle.isEmpty ? "—" : result.filteredPortsTitle)
                }
                .width(min: 80, ideal: 100)
                .customizationID("nettoys.filtered-ports")
                .defaultVisibility(.hidden)

                TableColumn("HTTP Server", value: \NetToysScanResult.httpServerTitle) { result in
                    Text(result.httpServerTitle.isEmpty ? "—" : result.httpServerTitle)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 150)
                .customizationID("nettoys.http-server")
                .defaultVisibility(.hidden)

                TableColumn("HTTP Proxy", value: \NetToysScanResult.httpProxyTitle) { result in
                    Text(result.httpProxyTitle.isEmpty ? "—" : result.httpProxyTitle)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 140)
                .customizationID("nettoys.http-proxy")
                .defaultVisibility(.hidden)

                TableColumn("Custom Text", value: \NetToysScanResult.customTextTitle) { result in
                    Text(result.customTextTitle.isEmpty ? "—" : result.customTextTitle)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 160)
                .customizationID("nettoys.custom-text")
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
            Button("Copy Details") {
                copyDetails(model.results.filter { selected.contains($0.id) })
            }
            Button("Rescan") {
                model.start(targets: model.results.filter { selected.contains($0.id) }.map(\.address))
            }
            .disabled(model.isScanning)
            Button("Delete", role: .destructive) {
                model.removeResults(ids: selected)
                model.selection.subtract(selected)
            }
        } primaryAction: { selected in
            detailResult = model.results.first { selected.contains($0.id) }
        }
        .thinScrollIndicators()
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isScanning {
                ProgressView(value: Double(model.completed), total: Double(max(model.total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("\(model.completed) of \(model.total)")
                    .monospacedDigit()
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
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .frame(height: 30)
    }

    private var scanSubtitle: String? {
        if model.isScanning { return "Scanning \(model.total) addresses" }
        return model.results.isEmpty ? "Enter a target and one or more TCP ports" : nil
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scan Statistics")
                    .font(.title2.weight(.semibold))
                Spacer()
                UtilityModalCloseButton { dismiss() }
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
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
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(1)))) ms" } ?? "Not available"
    }
}

private struct NetToysScannerSettingsView: View {
    @Bindable var model: NetToysScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var openers: [NetToysOpener]

    init(model: NetToysScannerViewModel) {
        self.model = model
        _openers = State(initialValue: model.openers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scanner Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                UtilityModalCloseButton(action: saveAndDismiss)
            }

            Form {
                SingleStepStepper("TCP timeout: \(model.timeoutMilliseconds) ms", value: $model.timeoutMilliseconds, in: 100...5_000, step: 100)
                SingleStepStepper("Parallel connections: \(model.concurrency)", value: $model.concurrency, in: 1...256)
                SingleStepStepper(
                    "Launch delay: \(model.launchDelayMilliseconds) ms",
                    value: $model.launchDelayMilliseconds,
                    in: 0...100,
                    step: 5
                )
                Section("Host detection") {
                    Picker("Liveness", selection: $model.livenessMethod) {
                        ForEach(NetToysLivenessMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    Toggle("Use response-based TCP timeout", isOn: $model.adaptiveTCPTimeout)
                    if model.livenessMethod == .icmpAndTCP {
                        Toggle("Scan hosts that do not answer ICMP", isOn: $model.scanUnresponsiveHosts)
                    }
                    Toggle("Collect ICMP TTL and packet loss", isOn: $model.collectPingDetails)
                    if model.collectPingDetails || model.livenessMethod == .icmpAndTCP || model.adaptiveTCPTimeout {
                        SingleStepStepper("ICMP timeout: \(model.pingTimeoutMilliseconds) ms", value: $model.pingTimeoutMilliseconds, in: 100...5_000, step: 100)
                        SingleStepStepper("ICMP probes: \(model.pingProbeCount)", value: $model.pingProbeCount, in: 1...5)
                    }
                }

                Section("Protocol fetchers") {
                    Toggle("Detect HTTP servers", isOn: $model.detectHTTPServer)
                    Toggle("Detect HTTP proxies", isOn: $model.detectHTTPProxy)
                    Toggle("Read NetBIOS names", isOn: $model.detectNetBIOS)
                    Toggle("Use custom text probe", isOn: $model.customTextEnabled)
                    if model.customTextEnabled {
                        SingleStepStepper("Custom port: \(model.customTextPort)", value: $model.customTextPort, in: 1...65_535)
                        TextField("Request", text: $model.customTextRequest, axis: .vertical)
                            .lineLimit(2...4)
                        TextField("Response regular expression", text: $model.customTextPattern)
                    }
                }

                Section("MAC addresses") {
                    Text("macOS restricts neighboring device MAC addresses to processes with Apple's private neighbor-cache privilege. NetToys never presents the system's privacy placeholder as a device MAC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Openers") {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("Name")
                            Text("URL template")
                            Text("Port")
                            Color.clear.frame(width: 20)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(Array(openers.enumerated()), id: \.element.id) { index, opener in
                            GridRow {
                                TextField("Name", text: $openers[index].name)
                                    .frame(width: 110)
                                TextField("URL template", text: $openers[index].urlTemplate)
                                    .frame(minWidth: 280)
                                TextField("Port", value: $openers[index].requiredPort, format: .number)
                                    .frame(width: 60)
                                Button(role: .destructive) {
                                    openers.removeAll { $0.id == opener.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .focusEffectDisabled()
                                .accessibilityLabel("Delete \(opener.name) opener")
                            }
                        }
                    }

                    HStack {
                        Button("Add Opener") {
                            guard openers.count < 20 else { return }
                            openers.append(NetToysOpener(
                                name: "New Opener",
                                urlTemplate: "http://{ip}:{port}/",
                                requiredPort: 80
                            ))
                        }
                        Button("Restore Defaults") { openers = NetToysOpener.defaults }
                    }
                    Text("Use {ip}, {hostname}, and {port}. NetToys opens only URL protocols and always shows a preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .thinScrollIndicators()
            .formStyle(.grouped)
            .controlSize(.small)

            HStack {
                Spacer()
                Button("Done", action: saveAndDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 700)
        .onDisappear { model.savePreferences() }
        .alert("Openers", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func saveAndDismiss() {
        do {
            try model.saveOpeners(openers)
            model.savePreferences()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Open with \(preview.name)?")
                    .font(.title2.weight(.semibold))
                Spacer()
                UtilityModalCloseButton { dismiss() }
            }
            Text("Review the complete URL before another app opens it.")
                .foregroundStyle(.secondary)
            Text(preview.url.absoluteString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Open") {
                    NSWorkspace.shared.open(preview.url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 560)
    }
}

private struct NetToysRandomTargetsView: View {
    @Bindable var model: NetToysScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cidr = LocalIPv4Network.active()?.cidr ?? "192.168.1.0/24"
    @State private var count = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Random Targets")
                    .font(.title2.weight(.semibold))
                Spacer()
                UtilityModalCloseButton { dismiss() }
            }
            Text("Generate unique usable IPv4 addresses inside one CIDR block.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Form {
                TextField("CIDR", text: $cidr)
                SingleStepStepper("Address count: \(count)", value: $count, in: 1...1_024)
            }
            .thinScrollIndicators()
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Generate") {
                    model.generateRandomTargets(cidr: cidr, count: count)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 430)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.address.description)
                        .font(.title2.weight(.semibold).monospaced())
                    Text(result.hostnameTitle.isEmpty ? "No reverse hostname" : result.hostnameTitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Favorite", isOn: $annotation.isFavorite)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                UtilityModalCloseButton { dismiss() }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
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
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("COMMENT").utilitySectionHeader()
                TextEditor(text: $annotation.comment)
                    .thinScrollIndicators()
                    .font(.system(size: 12))
                    .frame(height: 84)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.saveAnnotation(annotation, for: result.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 470)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
