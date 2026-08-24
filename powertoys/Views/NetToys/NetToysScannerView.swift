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

enum NetToysColumn: String, CaseIterable, Identifiable {
    case status = "Status"
    case response = "Response"
    case ttl = "TTL"
    case packetLoss = "Packet Loss"
    case hostname = "Hostname"
    case macAddress = "MAC Address"
    case openPorts = "Open Ports"
    case filteredPorts = "Filtered Ports"

    var id: String { rawValue }

    static let defaults: Set<Self> = [.status, .response, .hostname, .macAddress, .openPorts]
}

enum NetToysExportFormat: String, CaseIterable, Identifiable {
    case savedResults = "NetToys Results"
    case csv = "CSV"
    case text = "Text"
    case xml = "XML"
    case ipPorts = "IP and Port"
    case sql = "SQL"

    var id: String { rawValue }

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
    nonisolated var macTitle: String { macAddress ?? "" }
    nonisolated var portsTitle: String { openPorts.map(String.init).joined(separator: ", ") }
    nonisolated var filteredPortsTitle: String { filteredPorts?.map(String.init).joined(separator: ", ") ?? "" }
    nonisolated var ttlTitle: String { ttl.map(String.init) ?? "" }
    nonisolated var packetLossTitle: String {
        packetLossPercent.map { String(format: "%.1f", $0) } ?? ""
    }
}

@Observable
@MainActor
final class NetToysScannerViewModel {
    var targetInput: String
    var portInput = "22, 80, 443"
    var results: [NetToysScanResult] = []
    var filter = NetToysResultFilter.all
    var searchText = ""
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
    var visibleColumns = NetToysColumn.defaults {
        didSet {
            UserDefaults.standard.set(visibleColumns.map(\.rawValue).sorted(), forKey: "nettoys.scanner.columns")
        }
    }
    var favoriteTargets = NetToysScannerStore.favoriteTargets()
    var annotations = NetToysScannerStore.annotations()

    private let scanner = NetToysScanner()
    private var scanTask: Task<Void, Never>?

    init() {
        targetInput = LocalIPv4Network.active()?.cidr ?? "192.168.1.0/24"
        if let saved = UserDefaults.standard.stringArray(forKey: "nettoys.scanner.columns") {
            let columns = Set(saved.compactMap(NetToysColumn.init(rawValue:)))
            if !columns.isEmpty { visibleColumns = columns }
        }
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
            return ([result.address.description, result.hostnameTitle, result.macTitle, result.portsTitle]
                + [annotations[result.id]?.comment ?? ""])
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func start(targets override: [IPv4Address]? = nil) {
        guard !isScanning else { return }
        do {
            let defaultPorts = try PortList.parse(portInput)
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
                        launchDelayMilliseconds: launchDelayMilliseconds
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

struct NetToysScannerView: View {
    @State private var model = NetToysScannerViewModel()
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\NetToysScanResult.sortAddress)]
    @State private var showSettings = false
    @State private var showRandomTargets = false
    @State private var detailResult: NetToysScanResult?

    private var sortedResults: [NetToysScanResult] {
        model.visibleResults.sorted(using: sortOrder)
    }

    private var selectedRows: [NetToysScanResult] {
        model.results.filter { selection.contains($0.id) }
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
        .sheet(item: $detailResult) { result in
            NetToysHostDetailsView(model: model, result: result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysStartScan)) { notification in
            guard let run = notification.object as? NetToysScanRun else { return }
            model.targetInput = run.target
            model.portInput = run.ports.map(String.init).joined(separator: ", ")
            model.start()
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

            SearchField(text: $model.searchText, placeholder: "Find address, host, MAC, or port")
                .frame(maxWidth: 320)

            Spacer()

            Menu("More") {
                Button("Next Alive Host") { selectNext(where: \.isReachable) }
                Button("Next Down Host") { selectNext { !$0.isReachable } }
                Button("Next Host With Open Ports") { selectNext { !$0.openPorts.isEmpty } }
                Divider()
                Button("Delete Selected", role: .destructive) {
                    model.removeResults(ids: selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }

            Button("Copy IP") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selectedRows.map { $0.address.description }.joined(separator: "\n"), forType: .string)
            }
            .disabled(selection.isEmpty)

            Button("Rescan") {
                model.start(targets: selectedRows.map(\.address))
            }
            .disabled(selection.isEmpty || model.isScanning)

            Menu("Export") {
                ForEach(NetToysExportFormat.allCases) { format in
                    Button(format.rawValue) {
                        model.export(format, rows: selectedRows.isEmpty ? sortedResults : selectedRows)
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
        Table(sortedResults, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("IP Address", value: \.sortAddress) { result in
                Text(result.address.description)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 112, ideal: 126)

            if model.visibleColumns.contains(.status) {
                TableColumn("Status", value: \.statusTitle) { result in
                    Label(result.statusTitle, systemImage: result.isReachable ? "circle.fill" : "circle")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(result.isReachable ? .green : .secondary)
                }
                .width(min: 68, ideal: 76)
            }

            if model.visibleColumns.contains(.response) {
                TableColumn("Response", value: \.responseTitle) { result in
                    Text(result.responseTitle.isEmpty ? "—" : "\(result.responseTitle) ms")
                        .monospacedDigit()
                }
                .width(min: 76, ideal: 86)
            }

            if model.visibleColumns.contains(.ttl) {
                TableColumn("TTL", value: \.ttlTitle) { result in
                    Text(result.ttlTitle.isEmpty ? "—" : result.ttlTitle)
                }
                .width(min: 44, ideal: 48)
            }

            if model.visibleColumns.contains(.packetLoss) {
                TableColumn("Loss", value: \.packetLossTitle) { result in
                    Text(result.packetLossTitle.isEmpty ? "—" : "\(result.packetLossTitle)%")
                        .monospacedDigit()
                }
                .width(min: 58, ideal: 66)
            }

            if model.visibleColumns.contains(.hostname) {
                TableColumn("Hostname", value: \.hostnameTitle) { result in
                    Text(result.hostnameTitle.isEmpty ? "—" : result.hostnameTitle)
                        .lineLimit(1)
                }
                .width(min: 116, ideal: 154)
            }

            if model.visibleColumns.contains(.macAddress) {
                TableColumn("MAC Address", value: \.macTitle) { result in
                    Text(result.macTitle.isEmpty ? "—" : result.macTitle)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 130, ideal: 142)
            }

            if model.visibleColumns.contains(.openPorts) {
                TableColumn("Open Ports", value: \.portsTitle) { result in
                    Text(result.portsTitle.isEmpty ? "—" : result.portsTitle)
                }
                .width(min: 86, ideal: 106)
            }

            if model.visibleColumns.contains(.filteredPorts) {
                TableColumn("Filtered", value: \.filteredPortsTitle) { result in
                    Text(result.filteredPortsTitle.isEmpty ? "—" : result.filteredPortsTitle)
                }
                .width(min: 80, ideal: 100)
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
                Divider()
                if result.openPorts.contains(22) {
                    Button("Open SSH") { open(result, scheme: "ssh", port: 22) }
                }
                if result.openPorts.contains(80) {
                    Button("Open HTTP") { open(result, scheme: "http", port: 80) }
                }
                if result.openPorts.contains(443) {
                    Button("Open HTTPS") { open(result, scheme: "https", port: 443) }
                }
                Divider()
            }
            Button("Copy IP Address") {
                let rows = model.results.filter { selected.contains($0.id) }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rows.map { $0.address.description }.joined(separator: "\n"), forType: .string)
            }
            Button("Rescan") {
                model.start(targets: model.results.filter { selected.contains($0.id) }.map(\.address))
            }
            .disabled(model.isScanning)
            Button("Delete", role: .destructive) {
                model.removeResults(ids: selected)
                selection.subtract(selected)
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

    private func open(_ result: NetToysScanResult, scheme: String, port: UInt16) {
        var components = URLComponents()
        components.scheme = scheme
        components.host = result.address.description
        if !((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) {
            components.port = Int(port)
        }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func selectNext(where predicate: (NetToysScanResult) -> Bool) {
        let matches = sortedResults.filter(predicate)
        guard !matches.isEmpty else { return }
        let current = selection.first.flatMap { id in matches.firstIndex { $0.id == id } }
        let next = matches[(current.map { ($0 + 1) % matches.count }) ?? 0]
        selection = [next.id]
    }
}

private struct NetToysScannerSettingsView: View {
    @Bindable var model: NetToysScannerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scanner Settings")
                .font(.title2.weight(.semibold))

            Form {
                Stepper("Timeout: \(model.timeoutMilliseconds) ms", value: $model.timeoutMilliseconds, in: 100...5_000, step: 100)
                Stepper("Parallel connections: \(model.concurrency)", value: $model.concurrency, in: 1...256)
                Stepper(
                    "Launch delay: \(model.launchDelayMilliseconds) ms",
                    value: $model.launchDelayMilliseconds,
                    in: 0...100,
                    step: 5
                )
                Toggle("Collect ICMP TTL and packet loss", isOn: $model.collectPingDetails)
                if model.collectPingDetails {
                    Stepper("ICMP probes: \(model.pingProbeCount)", value: $model.pingProbeCount, in: 1...5)
                }

                Section("Visible columns") {
                    ForEach(NetToysColumn.allCases) { column in
                        Toggle(column.rawValue, isOn: Binding(
                            get: { model.visibleColumns.contains(column) },
                            set: { enabled in
                                if enabled {
                                    model.visibleColumns.insert(column)
                                } else {
                                    model.visibleColumns.remove(column)
                                }
                            }
                        ))
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}

private struct NetToysRandomTargetsView: View {
    @Bindable var model: NetToysScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cidr = LocalIPv4Network.active()?.cidr ?? "192.168.1.0/24"
    @State private var count = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Random Targets")
                .font(.title2.weight(.semibold))
            Text("Generate unique usable IPv4 addresses inside one CIDR block.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Form {
                TextField("CIDR", text: $cidr)
                Stepper("Address count: \(count)", value: $count, in: 1...1_024)
            }
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
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("COMMENT").utilitySectionHeader()
                TextEditor(text: $annotation.comment)
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
