import AppKit
import Foundation

nonisolated enum SystemCareMode: String, CaseIterable, Identifiable {
    case quick = "Quick Cleanup"
    case guided = "Guided Cleanup"
    case analysis = "Analysis Only"

    var id: String { rawValue }
}

nonisolated enum SystemCareCategoryID: String, CaseIterable, Identifiable, Sendable {
    case caches
    case logs
    case installers
    case developer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .caches: "Application Caches"
        case .logs: "User Logs"
        case .installers: "Downloaded Installers"
        case .developer: "Xcode Derived Data"
        }
    }
    var detail: String {
        switch self {
        case .caches: "Rebuildable files in ~/Library/Caches"
        case .logs: "Old diagnostic files in ~/Library/Logs"
        case .installers: "DMG, PKG, MPKG, ISO, and XIP files in Downloads"
        case .developer: "Rebuildable Xcode output in DerivedData"
        }
    }
    var icon: String {
        switch self {
        case .caches: "shippingbox"
        case .logs: "doc.text"
        case .installers: "opticaldiscdrive"
        case .developer: "hammer"
        }
    }
}

nonisolated struct CleanupCandidate: Identifiable, Hashable, Sendable {
    let url: URL
    let allowedRoot: URL
    let category: SystemCareCategoryID
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

nonisolated struct StorageEntry: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    let size: Int64
    let isDirectory: Bool

    var id: String { url.path }
}

nonisolated struct InstalledApplication: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    var id: String { url.path }
}

nonisolated struct MoleHistoryItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
}

nonisolated enum MoleOperation: String, CaseIterable, Identifiable {
    case clean
    case optimize
    case purge
    case installer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: "Deep Cleanup"
        case .optimize: "System Maintenance"
        case .purge: "Project Artifacts"
        case .installer: "Installer Files"
        }
    }
    var detail: String {
        switch self {
        case .clean: "Caches, logs, temporary files, and orphaned leftovers"
        case .optimize: "Safe cache and service maintenance"
        case .purge: "Rebuildable artifacts in development projects"
        case .installer: "DMG, PKG, ISO, XIP, and installer ZIP files"
        }
    }
    var icon: String {
        switch self {
        case .clean: "sparkles"
        case .optimize: "wrench.and.screwdriver"
        case .purge: "hammer"
        case .installer: "opticaldiscdrive"
        }
    }
}

@Observable
@MainActor
final class SystemCareManager {
    static let shared = SystemCareManager()

    private(set) var molePath: URL?
    private(set) var moleVersion: String?
    private(set) var isWorking = false
    private(set) var progressMessage: String?
    private(set) var errorMessage: String?
    private(set) var cleanupCandidates: [CleanupCandidate] = []
    private(set) var selectedCandidateIDs: Set<String> = []
    private(set) var storageEntries: [StorageEntry] = []
    private(set) var storageTotal: Int64 = 0
    private(set) var storageFileCount = 0
    private(set) var storageURL: URL?
    private(set) var storageBreadcrumbs: [URL] = []
    private(set) var applications: [InstalledApplication] = []
    private(set) var history: [MoleHistoryItem] = []
    private(set) var lastRecoveredBytes: Int64 = 0

    private var task: Task<Void, Never>?

    private init() {}

    func refresh() {
        task?.cancel()
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .utility) {
                (Self.detectMole(), Self.installedApplications())
            }.value
            guard !Task.isCancelled else { return }
            molePath = result.0.path
            moleVersion = result.0.version
            applications = result.1
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isWorking = false
        progressMessage = nil
    }

    func scanCleanup(categories: Set<SystemCareCategoryID>) {
        task?.cancel()
        isWorking = true
        errorMessage = nil
        progressMessage = "Scanning selected locations…"
        task = Task { [weak self] in
            do {
                let candidates = try await Task.detached(priority: .utility) {
                    try Self.cleanupCandidates(for: categories)
                }.value
                try Task.checkCancellation()
                self?.cleanupCandidates = candidates
                self?.selectedCandidateIDs = Set(candidates.map(\.id))
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isWorking = false
            self?.progressMessage = nil
        }
    }

    func setCandidate(_ id: String, selected: Bool) {
        if selected { selectedCandidateIDs.insert(id) }
        else { selectedCandidateIDs.remove(id) }
    }

    func moveSelectedToTrash() {
        let candidates = cleanupCandidates.filter { selectedCandidateIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        progressMessage = "Moving selected items to Trash…"
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                var recovered: Int64 = 0
                var failures: [String] = []
                for candidate in candidates {
                    guard Self.isSafe(candidate) else {
                        failures.append(candidate.name)
                        continue
                    }
                    do {
                        try FileManager.default.trashItem(at: candidate.url, resultingItemURL: nil)
                        recovered += candidate.size
                    } catch {
                        failures.append(candidate.name)
                    }
                }
                return (recovered, failures)
            }.value
            self?.lastRecoveredBytes = outcome.0
            self?.cleanupCandidates.removeAll { self?.selectedCandidateIDs.contains($0.id) == true }
            self?.selectedCandidateIDs.removeAll()
            self?.isWorking = false
            self?.progressMessage = nil
            if !outcome.1.isEmpty {
                self?.errorMessage = "Could not move \(outcome.1.count) item(s) to Trash."
            }
        }
    }

    func analyze(_ url: URL, resetBreadcrumbs: Bool = false) {
        task?.cancel()
        isWorking = true
        errorMessage = nil
        progressMessage = "Analyzing \(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)…"
        let mole = molePath
        task = Task { [weak self] in
            do {
                let report = try await Task.detached(priority: .utility) {
                    if let mole {
                        return try Self.moleAnalyze(executable: mole, url: url)
                    }
                    return try Self.nativeAnalyze(url: url)
                }.value
                try Task.checkCancellation()
                self?.storageURL = url
                self?.storageEntries = report.entries
                self?.storageTotal = report.totalSize
                self?.storageFileCount = report.totalFiles
                if resetBreadcrumbs || self?.storageBreadcrumbs.isEmpty == true {
                    self?.storageBreadcrumbs = [url]
                } else if self?.storageBreadcrumbs.last != url {
                    self?.storageBreadcrumbs.append(url)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isWorking = false
            self?.progressMessage = nil
        }
    }

    func navigateStorage(to url: URL) {
        if let index = storageBreadcrumbs.firstIndex(of: url) {
            storageBreadcrumbs = Array(storageBreadcrumbs.prefix(index + 1))
        }
        analyze(url)
    }

    func loadHistory() {
        guard let molePath else {
            history = []
            return
        }
        task?.cancel()
        isWorking = true
        task = Task { [weak self] in
            do {
                let items = try await Task.detached(priority: .utility) {
                    try Self.moleHistory(executable: molePath)
                }.value
                self?.history = items
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isWorking = false
        }
    }

    func installOrUpdateMole() {
        guard let brew = Self.firstExecutable(paths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            errorMessage = "Homebrew was not found. Install Mole from its official instructions instead."
            return
        }
        isWorking = true
        errorMessage = nil
        progressMessage = molePath == nil ? "Installing Mole with Homebrew…" : "Updating Mole with Homebrew…"
        let arguments = molePath == nil ? ["install", "mole"] : ["upgrade", "mole"]
        task = Task { [weak self] in
            do {
                let installation = try await Task.detached(priority: .utility) {
                    try Self.run(executable: brew, arguments: arguments)
                    return Self.detectMole()
                }.value
                self?.molePath = installation.path
                self?.moleVersion = installation.version
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isWorking = false
            self?.progressMessage = nil
        }
    }

    func openMole(_ operation: MoleOperation, dryRun: Bool) {
        guard let molePath else { return }
        openTerminal(arguments: [operation.rawValue] + (dryRun ? ["--dry-run"] : []), executable: molePath)
    }

    func openMoleUninstall(_ application: InstalledApplication, dryRun: Bool) {
        guard let molePath else { return }
        openTerminal(
            arguments: ["uninstall"] + (dryRun ? ["--dry-run"] : []) + [application.name],
            executable: molePath
        )
    }

    func openMoleWhitelist() {
        guard let molePath else { return }
        openTerminal(arguments: ["clean", "--whitelist"], executable: molePath)
    }

    var selectedSize: Int64 {
        cleanupCandidates.lazy
            .filter { self.selectedCandidateIDs.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    private func openTerminal(arguments: [String], executable: URL) {
        let command = ([executable.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
        let source = "#!/bin/zsh\ntrap 'rm -f -- \"$0\"' EXIT\nclear\n\(command)\nprintf '\\nPress Return to close…'\nread\n"
        Task { [weak self] in
            do {
                let script = try await Task.detached(priority: .userInitiated) {
                    try Self.makeTerminalScript(source)
                }.value
                NSWorkspace.shared.open(script)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated private static func makeTerminalScript(_ source: String) throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPowerToys-SystemCare-\(UUID().uuidString).command")
        try Data(source.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    nonisolated private static func cleanupCandidates(
        for categories: Set<SystemCareCategoryID>
    ) throws -> [CleanupCandidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result: [CleanupCandidate] = []
        for category in categories {
            try Task.checkCancellation()
            let root: URL
            switch category {
            case .caches: root = home.appendingPathComponent("Library/Caches", isDirectory: true)
            case .logs: root = home.appendingPathComponent("Library/Logs", isDirectory: true)
            case .installers: root = home.appendingPathComponent("Downloads", isDirectory: true)
            case .developer: root = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in children.prefix(500) {
                try Task.checkCancellation()
                if category == .installers {
                    let extensions = Set(["dmg", "pkg", "mpkg", "iso", "xip"])
                    guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                }
                result.append(CleanupCandidate(
                    url: url,
                    allowedRoot: root,
                    category: category,
                    size: try allocatedSize(of: url)
                ))
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    nonisolated private static func allocatedSize(of url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let childValues = try? child.resourceValues(forKeys: keys)
            if childValues?.isSymbolicLink == true {
                enumerator.skipDescendants()
            } else if childValues?.isDirectory != true {
                total += Int64(childValues?.totalFileAllocatedSize ?? childValues?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    nonisolated static func isSafe(_ candidate: CleanupCandidate) -> Bool {
        let root = candidate.allowedRoot.standardizedFileURL.path
        let path = candidate.url.standardizedFileURL.path
        return path != root && path.hasPrefix(root + "/")
    }

    nonisolated private static func nativeAnalyze(url: URL) throws -> StorageReport {
        let children = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [StorageEntry] = []
        var total: Int64 = 0
        for child in children {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            let size = try allocatedSize(of: child)
            total += size
            entries.append(StorageEntry(
                name: child.lastPathComponent,
                url: child,
                size: size,
                isDirectory: values?.isDirectory == true
            ))
        }
        entries.sort { $0.size > $1.size }
        return StorageReport(entries: entries, totalSize: total, totalFiles: entries.count)
    }

    nonisolated private static func moleAnalyze(executable: URL, url: URL) throws -> StorageReport {
        let data = try run(executable: executable, arguments: ["analyze", "--json", url.path])
        let report = try JSONDecoder().decode(MoleAnalyzeReport.self, from: data)
        return StorageReport(
            entries: report.entries.map {
                StorageEntry(name: $0.name, url: URL(fileURLWithPath: $0.path), size: $0.size, isDirectory: $0.isDir)
            }.sorted { $0.size > $1.size },
            totalSize: report.totalSize,
            totalFiles: report.totalFiles
        )
    }

    nonisolated private static func moleHistory(executable: URL) throws -> [MoleHistoryItem] {
        let data = try run(executable: executable, arguments: ["history", "--json", "--limit", "100"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let rows = (root["sessions"] as? [[String: Any]] ?? []) + (root["deletions"] as? [[String: Any]] ?? [])
        return rows.map { row in
            let title = (row["operation"] ?? row["command"] ?? row["path"] ?? "Mole operation") as? String ?? "Mole operation"
            let detail = row.keys.sorted().map { "\($0): \(row[$0] ?? "")" }.joined(separator: " · ")
            return MoleHistoryItem(title: title, detail: detail)
        }
    }

    nonisolated private static func detectMole() -> (path: URL?, version: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo", "\(home)/.local/bin/mo"]
        guard let path = firstExecutable(paths: paths) else { return (nil, nil) }
        let output = (try? run(executable: path, arguments: ["--version"]))
            .flatMap { String(data: $0, encoding: .utf8) }
        let version = output?.split(separator: "\n").first(where: { $0.contains("Mole version") })
            .map { $0.replacingOccurrences(of: "Mole version ", with: "") }
        return (path, version)
    }

    nonisolated private static func installedApplications() -> [InstalledApplication] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
            .flatMap { root in
                (try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            .filter { $0.pathExtension.lowercased() == "app" }
            .map { InstalledApplication(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func firstExecutable(paths: [String]) -> URL? {
        paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    nonisolated private static func run(executable: URL, arguments: [String]) throws -> Data {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPowerToys-SystemCare-\(UUID().uuidString).output")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        try output.synchronize()
        let data = try Data(contentsOf: outputURL)
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8) ?? "The command failed."
            throw NSError(domain: "SystemCare", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

nonisolated private struct StorageReport: Sendable {
    let entries: [StorageEntry]
    let totalSize: Int64
    let totalFiles: Int
}

nonisolated private struct MoleAnalyzeReport: Decodable, Sendable {
    nonisolated struct Entry: Decodable, Sendable {
        let name: String
        let path: String
        let size: Int64
        let isDir: Bool

        enum CodingKeys: String, CodingKey {
            case name, path, size
            case isDir = "is_dir"
        }
    }

    let entries: [Entry]
    let totalSize: Int64
    let totalFiles: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case totalSize = "total_size"
        case totalFiles = "total_files"
    }
}
