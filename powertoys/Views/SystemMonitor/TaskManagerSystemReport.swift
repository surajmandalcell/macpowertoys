import AppKit
import Foundation
import OnePlusUI
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct TaskManagerReportRow: Sendable {
    let field: String
    let value: String
}

nonisolated struct TaskManagerReportSection: Identifiable, Sendable {
    let title: String
    let rows: [TaskManagerReportRow]
    var id: String { title }
}

nonisolated struct TaskManagerReportCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let group: String
    let sections: [TaskManagerReportSection]
}

nonisolated enum TaskManagerSystemReportParser {
    struct Source: Sendable {
        let id: String
        let title: String
        let symbol: String
        let group: String
        let dataType: String
    }

    static let sources: [Source] = [
        Source(id: "hardware", title: "Hardware overview", symbol: "desktopcomputer", group: "Hardware", dataType: "SPHardwareDataType"),
        Source(id: "memory", title: "Memory", symbol: "memorychip", group: "Hardware", dataType: "SPMemoryDataType"),
        Source(id: "graphics", title: "Graphics / Displays", symbol: "display", group: "Hardware", dataType: "SPDisplaysDataType"),
        Source(id: "storage", title: "Storage", symbol: "internaldrive", group: "Hardware", dataType: "SPStorageDataType"),
        Source(id: "nvme", title: "NVMExpress", symbol: "externaldrive", group: "Hardware", dataType: "SPNVMeDataType"),
        Source(id: "usb", title: "USB", symbol: "cable.connector", group: "Hardware", dataType: "SPUSBDataType"),
        Source(id: "thunderbolt", title: "Thunderbolt / USB4", symbol: "bolt.horizontal", group: "Hardware", dataType: "SPThunderboltDataType"),
        Source(id: "audio", title: "Audio", symbol: "speaker.wave.2", group: "Hardware", dataType: "SPAudioDataType"),
        Source(id: "camera", title: "Camera", symbol: "camera", group: "Hardware", dataType: "SPCameraDataType"),
        Source(id: "power", title: "Power", symbol: "bolt", group: "Hardware", dataType: "SPPowerDataType"),
        Source(id: "network", title: "Network overview", symbol: "network", group: "Network", dataType: "SPNetworkDataType"),
        Source(id: "wifi", title: "Wi-Fi", symbol: "wifi", group: "Network", dataType: "SPAirPortDataType"),
        Source(id: "ethernet", title: "Ethernet", symbol: "cable.connector.horizontal", group: "Network", dataType: "SPEthernetDataType"),
        Source(id: "software", title: "Software overview", symbol: "gearshape.2", group: "Software", dataType: "SPSoftwareDataType"),
        Source(id: "applications", title: "Applications", symbol: "square.grid.2x2", group: "Software", dataType: "SPApplicationsDataType"),
        Source(id: "extensions", title: "Extensions", symbol: "puzzlepiece.extension", group: "Software", dataType: "SPExtensionsDataType"),
        Source(id: "developer", title: "Developer tools", symbol: "chevron.left.forwardslash.chevron.right", group: "Software", dataType: "SPDeveloperToolsDataType"),
    ]

    static func parse(data: Data, sources: [Source] = sources) throws -> [TaskManagerReportCategory] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return sources.compactMap { source in
            guard let rawItems = root[source.dataType] as? [Any] else { return nil }
            let sections = sections(from: rawItems, fallbackTitle: source.title)
            guard !sections.isEmpty else { return nil }
            return TaskManagerReportCategory(
                id: source.id,
                title: source.title,
                symbol: source.symbol,
                group: source.group,
                sections: sections
            )
        }
    }

    private static func sections(from items: [Any], fallbackTitle: String) -> [TaskManagerReportSection] {
        var output: [TaskManagerReportSection] = []
        for (index, item) in items.enumerated() {
            guard let dictionary = item as? [String: Any] else { continue }
            let title = (dictionary["_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (items.count == 1 ? fallbackTitle : "\(fallbackTitle) \(index + 1)")
            var rows: [TaskManagerReportRow] = []
            flatten(dictionary, prefix: "", depth: 0, rows: &rows)
            if !rows.isEmpty {
                output.append(TaskManagerReportSection(title: title, rows: Array(rows.prefix(250))))
            }
        }
        return output
    }

    private static func flatten(
        _ dictionary: [String: Any],
        prefix: String,
        depth: Int,
        rows: inout [TaskManagerReportRow]
    ) {
        guard depth < 4, rows.count < 250 else { return }
        for key in dictionary.keys.sorted() where !key.hasPrefix("_") && !isSensitive(key) {
            guard let value = dictionary[key] else { continue }
            let field = [prefix, label(key)].filter { !$0.isEmpty }.joined(separator: " · ")
            switch value {
            case let text as String:
                rows.append(TaskManagerReportRow(field: field, value: text.isEmpty ? "—" : text))
            case let number as NSNumber:
                rows.append(TaskManagerReportRow(field: field, value: number.stringValue))
            case let nested as [String: Any]:
                flatten(nested, prefix: field, depth: depth + 1, rows: &rows)
            case let array as [Any]:
                flatten(array, prefix: field, depth: depth + 1, rows: &rows)
            default:
                continue
            }
        }
    }

    private static func flatten(
        _ array: [Any],
        prefix: String,
        depth: Int,
        rows: inout [TaskManagerReportRow]
    ) {
        guard depth < 4, rows.count < 250 else { return }
        let scalarValues = array.compactMap { value -> String? in
            if let text = value as? String { return text }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        if scalarValues.count == array.count, !scalarValues.isEmpty {
            rows.append(TaskManagerReportRow(field: prefix, value: scalarValues.joined(separator: ", ")))
            return
        }
        for (index, value) in array.enumerated() {
            guard let nested = value as? [String: Any] else { continue }
            let name = nested["_name"] as? String ?? "Item \(index + 1)"
            flatten(nested, prefix: [prefix, name].filter { !$0.isEmpty }.joined(separator: " · "),
                    depth: depth + 1, rows: &rows)
        }
    }

    private static func isSensitive(_ key: String) -> Bool {
        let key = key.lowercased()
        return key.contains("serial") || key.contains("uuid")
            || key.contains("hardware_address") || key.contains("mac_address")
    }

    private static func label(_ key: String) -> String {
        let words = key
            .replacingOccurrences(of: "sp", with: "SP", options: [.anchored, .caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
        return words.enumerated().map { index, word in
            index == 0 ? word.capitalized : word.lowercased()
        }.joined(separator: " ")
    }
}

actor TaskManagerSystemReportLoader {
    static let shared = TaskManagerSystemReportLoader()
    private var cached: [TaskManagerReportCategory]?

    func load() async throws -> [TaskManagerReportCategory] {
        if let cached { return cached }
        let result = try await SSHProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
            arguments: ["-json", "-detailLevel", "mini"] + TaskManagerSystemReportParser.sources.map(\.dataType),
            maximumOutputBytes: 24 * 1_024 * 1_024,
            timeout: 60
        )
        guard result.status == 0 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: result.standardError])
        }
        let categories = try TaskManagerSystemReportParser.parse(data: Data(result.standardOutput.utf8))
        guard !categories.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        cached = categories
        return categories
    }
}

enum TaskManagerSystemReportAction: Equatable {
    case copy
    case exportText
    case exportJSON
}

nonisolated struct TaskManagerReportMatch: Identifiable, Sendable {
    let category: TaskManagerReportCategory
    let section: TaskManagerReportSection
    let row: TaskManagerReportRow
    let sectionIndex: Int
    let rowIndex: Int

    var id: String { "\(category.id):\(sectionIndex):\(rowIndex)" }
}

nonisolated enum TaskManagerReportSearch {
    static func matches(
        query: String,
        categories: [TaskManagerReportCategory]
    ) -> [TaskManagerReportMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return categories.flatMap { category in
            category.sections.enumerated().flatMap { sectionIndex, section in
                section.rows.enumerated().compactMap { rowIndex, row in
                    guard "\(category.title) \(section.title) \(row.field) \(row.value)"
                        .localizedCaseInsensitiveContains(query) else { return nil }
                    return TaskManagerReportMatch(
                        category: category,
                        section: section,
                        row: row,
                        sectionIndex: sectionIndex,
                        rowIndex: rowIndex
                    )
                }
            }
        }
    }
}

struct TaskManagerSystemReportView: View {
    @Binding var search: String
    @Binding var requestedAction: TaskManagerSystemReportAction?
    @State private var categories: [TaskManagerReportCategory] = []
    @State private var selectedID = "hardware"
    @State private var collapsedGroups = Set<String>()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var matches: [TaskManagerReportMatch] = []

    init(
        search: Binding<String>,
        requestedAction: Binding<TaskManagerSystemReportAction?>,
        initialCategories: [TaskManagerReportCategory] = []
    ) {
        _search = search
        _requestedAction = requestedAction
        _categories = State(initialValue: initialCategories)
        _isLoading = State(initialValue: initialCategories.isEmpty)
    }

    private let groups = ["Hardware", "Network", "Software"]
    private var selected: TaskManagerReportCategory? {
        categories.first { $0.id == selectedID } ?? categories.first
    }
    private var searchRequest: String { "\(categories.count):\(search)" }

    var body: some View {
        TaskManagerPanel {
            HStack(spacing: 0) {
                Group {
                    if categories.isEmpty { loadingTree } else { tree }
                }
                .frame(width: 180)
                Rectangle().fill(TaskManagerTheme.line).frame(width: 1)
                Group {
                    if isLoading {
                        loadingReport
                    } else if categories.isEmpty {
                        OnePlusEmptyState(
                            "System information unavailable",
                            systemImage: "exclamationmark.triangle",
                            caption: errorMessage ?? "Task Manager could not collect system information."
                        )
                    } else {
                    reportContent
                }
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .task(id: searchRequest) { await updateMatches() }
        .onChange(of: requestedAction) { _, action in
            guard let action else { return }
            switch action {
            case .copy: copyCurrent()
            case .exportText: export(format: .text)
            case .exportJSON: export(format: .json)
            }
            requestedAction = nil
        }
    }

    private var loadingTree: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.self) { group in
                Label(group, systemImage: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TaskManagerTheme.sidebar.opacity(0.56))
    }

    private var loadingReport: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(TaskManagerTheme.secondary)
                Text("System information")
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Collecting system information…")
                    .font(.system(size: 10))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
            .padding(18)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.self) { group in
                    let groupCategories = categories.filter { $0.group == group }
                    if !groupCategories.isEmpty {
                        Button {
                            if collapsedGroups.contains(group) { collapsedGroups.remove(group) }
                            else { collapsedGroups.insert(group) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: collapsedGroups.contains(group) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .semibold)).frame(width: 10)
                                Text(group).font(.system(size: 10, weight: .medium))
                                Spacer()
                            }
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 4)).focusEffectDisabled()
                        if !collapsedGroups.contains(group) {
                            ForEach(groupCategories) { category in
                                Button { selectedID = category.id; search = "" } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: category.symbol)
                                            .font(.system(size: 10)).frame(width: 13)
                                        Text(category.title).font(.system(size: 10)).lineLimit(1)
                                        Spacer(minLength: 2)
                                    }
                                    .foregroundStyle(selectedID == category.id ? TaskManagerTheme.ink : TaskManagerTheme.secondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 27)
                                    .contentShape(Rectangle())
                                    .background(selectedID == category.id ? Color.white.opacity(0.085) : .clear,
                                                in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 4)).focusEffectDisabled()
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .thinScrollIndicators()
        .background(TaskManagerTheme.sidebar.opacity(0.56))
    }

    @ViewBuilder
    private var reportContent: some View {
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let selected {
                categoryView(selected)
            }
        } else {
            searchResults
        }
    }

    private func categoryView(_ category: TaskManagerReportCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: category.symbol).font(.system(size: 14)).foregroundStyle(TaskManagerTheme.secondary)
                Text(category.title).font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(category.sections) { section in
                        reportSection(section)
                    }
                }
            }
            .thinScrollIndicators()
        }
    }

    private func reportSection(_ section: TaskManagerReportSection) -> some View {
        LazyVStack(spacing: 0) {
            HStack {
                Text(section.title).font(.system(size: 10, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Color.white.opacity(0.018))
            ForEach(section.rows.indices, id: \.self) { index in
                let row = section.rows[index]
                HStack(alignment: .top, spacing: 20) {
                    Text(row.field)
                        .font(.system(size: 9.5)).foregroundStyle(TaskManagerTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 9.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !matches.isEmpty {
                HStack {
                    Text("\(matches.count) matches")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                }
                .padding(18)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(matches) { match in
                            Button {
                                selectedID = match.category.id
                                search = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(match.category.title) · \(match.section.title)")
                                        .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.muted)
                                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                                        Text(match.row.field)
                                            .font(.system(size: 10))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(match.row.value)
                                            .font(.system(size: 10))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 0))
                            .focusEffectDisabled()
                            Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                        }
                    }
                }
            }
            .thinScrollIndicators()
        }
    }

    private func updateMatches() async {
        let query = search
        let categories = categories
        let result = await Task.detached(priority: .userInitiated) {
            TaskManagerReportSearch.matches(query: query, categories: categories)
        }.value
        guard !Task.isCancelled, search == query else { return }
        matches = result
    }

    private func load() async {
        guard categories.isEmpty else { return }
        isLoading = true
        do {
            categories = try await TaskManagerSystemReportLoader.shared.load()
            selectedID = categories.first?.id ?? selectedID
            errorMessage = nil
        } catch {
            errorMessage = "System information could not be collected: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func copyCurrent() {
        guard let selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textReport(categories: [selected]), forType: .string)
    }

    private enum ExportFormat { case text, json }

    private func export(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format == .text ? "Task Manager System Report.txt" : "Task Manager System Report.json"
        panel.allowedContentTypes = format == .text ? [.plainText] : [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let data: Data?
            switch format {
            case .text: data = Data(textReport(categories: categories).utf8)
            case .json: data = try? JSONSerialization.data(withJSONObject: jsonReport, options: [.prettyPrinted, .sortedKeys])
            }
            try? data?.write(to: url, options: .atomic)
        }
    }

    private func textReport(categories: [TaskManagerReportCategory]) -> String {
        categories.map { category in
            ([category.title] + category.sections.flatMap { section in
                ["\n\(section.title)"] + section.rows.map { "\($0.field): \($0.value)" }
            }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private var jsonReport: [[String: Any]] {
        categories.map { category in
            [
                "category": category.title,
                "sections": category.sections.map { section in
                    ["title": section.title, "rows": section.rows.map { ["field": $0.field, "value": $0.value] }]
                },
            ]
        }
    }
}
