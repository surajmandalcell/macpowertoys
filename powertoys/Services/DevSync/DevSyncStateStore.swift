import Foundation

nonisolated struct DevStateStoreIssue: Codable, Equatable, Sendable {
    var document: String
    var detail: String
    var occurredAt: Date
    var recoveredFromBackup: Bool
}

nonisolated private final class DevSyncISO8601Formatter: @unchecked Sendable {
    let value: ISO8601DateFormatter

    init(options: ISO8601DateFormatter.Options) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        value = formatter
    }
}

actor DevSyncStateStore {
    static let shared = DevSyncStateStore(
        rootURL: MainActor.assumeIsolated {
            AppDataLocation.directory.appendingPathComponent("DevSync", isDirectory: true)
        }
    )

    nonisolated let rootURL: URL
    private let fileManager = FileManager.default
    private var issueList: [DevStateStoreIssue] = []

    private static let metadataFileNames = [
        "projects.json",
        "links.json",
        "tombstones.json",
        "conflicts.json",
        "dirty.json",
        "cursors.json",
        "capabilities.json",
        "safety-records.json"
    ]

    private static let backupDateFormatter = DevSyncISO8601Formatter(
        options: [.withInternetDateTime, .withFractionalSeconds]
    )

    private static let dateFormatter = DevSyncISO8601Formatter(options: [.withInternetDateTime])

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    var issues: [DevStateStoreIssue] {
        issueList
    }

    nonisolated func pairDirectory(_ pairID: UUID) -> URL {
        rootURL.appendingPathComponent(pairID.uuidString, isDirectory: true)
    }

    nonisolated func internalSafetyHistoryDirectory(_ pairID: UUID) -> URL {
        pairDirectory(pairID)
            .appendingPathComponent("safety", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }

    func loadPairs() -> [DevSyncPair] {
        load([DevSyncPair].self, at: rootURL.appendingPathComponent("pairs.json"), document: "pairs.json") ?? []
    }

    func savePairs(_ pairs: [DevSyncPair]) throws {
        try save(pairs, at: rootURL.appendingPathComponent("pairs.json"))
    }

    func removePair(_ pairID: UUID) throws {
        _ = try backup(pairID: pairID)
        let directory = pairDirectory(pairID)
        guard !isSymbolicLink(directory), fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func loadProjects(pairID: UUID) -> [DevProject] {
        load([DevProject].self, at: pairFile(pairID, "projects.json"), document: "projects.json", pairID: pairID) ?? []
    }

    func saveProjects(_ projects: [DevProject], pairID: UUID) throws {
        try save(projects, at: pairFile(pairID, "projects.json"))
    }

    func loadBaseline(projectID: UUID, pairID: UUID) -> DevBaseline? {
        load(
            DevBaseline.self,
            at: pairFile(pairID, "baselines/\(projectID.uuidString).json"),
            document: "baselines/\(projectID.uuidString).json",
            pairID: pairID,
            preserveDatePrecision: false
        )
    }

    func saveBaseline(_ baseline: DevBaseline, pairID: UUID) throws {
        let url = pairFile(pairID, "baselines/\(baseline.projectID.uuidString).json")
        let data = try encode(baseline, preserveDatePrecision: false)
        // ponytail: JSON baseline documents; move to SQLite if load time exceeds budget
        try write(data, to: url)
    }

    func deleteBaseline(projectID: UUID, pairID: UUID) throws {
        let url = pairFile(pairID, "baselines/\(projectID.uuidString).json")
        guard !isSymbolicLink(url), fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func loadTombstones(pairID: UUID) -> [DevTombstone] {
        load([DevTombstone].self, at: pairFile(pairID, "tombstones.json"), document: "tombstones.json", pairID: pairID) ?? []
    }

    func saveTombstones(_ tombstones: [DevTombstone], pairID: UUID) throws {
        try save(tombstones, at: pairFile(pairID, "tombstones.json"))
    }

    func loadConflicts(pairID: UUID) -> [DevConflict] {
        load([DevConflict].self, at: pairFile(pairID, "conflicts.json"), document: "conflicts.json", pairID: pairID) ?? []
    }

    func saveConflicts(_ conflicts: [DevConflict], pairID: UUID) throws {
        try save(conflicts, at: pairFile(pairID, "conflicts.json"))
    }

    func loadLinks(pairID: UUID) -> [DevManagedLink] {
        load([DevManagedLink].self, at: pairFile(pairID, "links.json"), document: "links.json", pairID: pairID) ?? []
    }

    func saveLinks(_ links: [DevManagedLink], pairID: UUID) throws {
        try save(links, at: pairFile(pairID, "links.json"))
    }

    func loadDirty(pairID: UUID) -> [DevDirtyEntry] {
        load([DevDirtyEntry].self, at: pairFile(pairID, "dirty.json"), document: "dirty.json", pairID: pairID) ?? []
    }

    func saveDirty(_ entries: [DevDirtyEntry], pairID: UUID) throws {
        try save(entries, at: pairFile(pairID, "dirty.json"))
    }

    func loadCursors(pairID: UUID) -> [DevEventCursor] {
        load([DevEventCursor].self, at: pairFile(pairID, "cursors.json"), document: "cursors.json", pairID: pairID) ?? []
    }

    func saveCursors(_ cursors: [DevEventCursor], pairID: UUID) throws {
        try save(cursors, at: pairFile(pairID, "cursors.json"))
    }

    func loadCapabilities(pairID: UUID) -> DevPairCapabilities {
        load(DevPairCapabilities.self, at: pairFile(pairID, "capabilities.json"), document: "capabilities.json", pairID: pairID) ?? DevPairCapabilities()
    }

    func saveCapabilities(_ capabilities: DevPairCapabilities, pairID: UUID) throws {
        try save(capabilities, at: pairFile(pairID, "capabilities.json"))
    }

    func loadSafetyRecords(pairID: UUID) -> [DevSafetyRecord] {
        load([DevSafetyRecord].self, at: pairFile(pairID, "safety-records.json"), document: "safety-records.json", pairID: pairID) ?? []
    }

    func saveSafetyRecords(_ records: [DevSafetyRecord], pairID: UUID) throws {
        try save(records, at: pairFile(pairID, "safety-records.json"))
    }

    func saveOperation(_ operation: DevOperation) throws {
        try save(operation, at: pairFile(operation.pairID, "operations/\(operation.id.uuidString).json"))
    }

    func loadOperation(id: UUID, pairID: UUID) -> DevOperation? {
        load(
            DevOperation.self,
            at: pairFile(pairID, "operations/\(id.uuidString).json"),
            document: "operations/\(id.uuidString).json",
            pairID: pairID
        )
    }

    func loadOpenOperations(pairID: UUID) -> [DevOperation] {
        loadOperations(pairID: pairID, limit: .max).filter { !$0.state.isTerminal }
    }

    func loadOperations(pairID: UUID, limit: Int) -> [DevOperation] {
        guard limit > 0 else { return [] }
        let directory = pairFile(pairID, "operations")
        guard isDirectory(directory), let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" && !isSymbolicLink($0) }
            .compactMap { file in
                load(
                    DevOperation.self,
                    at: file,
                    document: "operations/\(file.lastPathComponent)",
                    pairID: pairID
                )
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString > $1.id.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }

    func deleteOperation(id: UUID, pairID: UUID) throws {
        let url = pairFile(pairID, "operations/\(id.uuidString).json")
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func backup(pairID: UUID) throws -> URL {
        let pairDirectory = self.pairDirectory(pairID)
        try createDirectory(pairDirectory)
        let backupsDirectory = pairDirectory.appendingPathComponent("backups", isDirectory: true)
        try createDirectory(backupsDirectory)

        let timestamp = Self.backupDateFormatter.value.string(from: Date())
        var backupDirectory = backupsDirectory.appendingPathComponent(timestamp, isDirectory: true)
        var suffix = 1
        while isSymbolicLink(backupDirectory) || fileManager.fileExists(atPath: backupDirectory.path) {
            backupDirectory = backupsDirectory.appendingPathComponent("\(timestamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try createDirectory(backupDirectory)

        for source in backupSources(pairID: pairID) where !isSymbolicLink(source.source) {
            guard fileManager.fileExists(atPath: source.source.path), let data = try? Data(contentsOf: source.source) else { continue }
            try write(data, to: backupDirectory.appendingPathComponent(source.relativePath))
        }

        let backupDirectories = directories(in: backupsDirectory).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for oldBackup in backupDirectories.dropFirst(5) {
            try fileManager.removeItem(at: oldBackup)
        }
        return backupDirectory
    }

    func restoreLatestBackup(pairID: UUID) throws -> Bool {
        guard let backupDirectory = latestBackupDirectory(pairID: pairID) else { return false }
        for source in backupSources(in: backupDirectory) where !isSymbolicLink(source.source) {
            guard let data = try? Data(contentsOf: source.source) else { continue }
            let destination = source.relativePath == "pairs.json"
                ? rootURL.appendingPathComponent(source.relativePath)
                : pairDirectory(pairID).appendingPathComponent(source.relativePath)
            try write(data, to: destination)
        }
        return true
    }

    private func pairFile(_ pairID: UUID, _ relativePath: String) -> URL {
        pairDirectory(pairID).appendingPathComponent(relativePath)
    }

    private func save<T: Encodable>(_ value: T, at url: URL) throws {
        try write(encode(value), to: url)
    }

    private func encode<T: Encodable>(_ value: T, preserveDatePrecision: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if preserveDatePrecision {
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(Self.iso8601String(from: date))
            }
        } else {
            encoder.dateEncodingStrategy = .iso8601
        }
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func decoder(preserveDatePrecision: Bool = true) -> JSONDecoder {
        let decoder = JSONDecoder()
        if preserveDatePrecision {
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                guard let date = Self.iso8601Date(from: value) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
                }
                return date
            }
        } else {
            decoder.dateDecodingStrategy = .iso8601
        }
        return decoder
    }

    private func load<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        document: String,
        pairID: UUID? = nil,
        preserveDatePrecision: Bool = true
    ) -> T? {
        guard !isSymbolicLink(url), fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            recordIssue(document: document, detail: "Document could not be read", recoveredFromBackup: false)
            return nil
        }
        do {
            return try decoder(preserveDatePrecision: preserveDatePrecision).decode(type, from: data)
        } catch {
            moveAside(url)
            guard let backupData = latestBackupData(document: document, pairID: pairID),
                  let recovered = try? decoder(preserveDatePrecision: preserveDatePrecision).decode(type, from: backupData) else {
                recordIssue(document: document, detail: "Document failed to decode", recoveredFromBackup: false)
                return nil
            }
            try? write(backupData, to: url)
            recordIssue(document: document, detail: "Document failed to decode", recoveredFromBackup: true)
            return recovered
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let timestamp = date.timeIntervalSinceReferenceDate
        let wholeSeconds = floor(timestamp)
        let fraction = timestamp - wholeSeconds
        let base = dateFormatter.value.string(from: Date(timeIntervalSinceReferenceDate: wholeSeconds))
        var candidate = fraction
        var digits = fractionDigits(candidate)
        for _ in 0..<10 {
            if let parsed = Double("0.\(digits)"), wholeSeconds + parsed == timestamp {
                return String(base.dropLast()) + ".\(digits)Z"
            }
            candidate = candidate.nextUp
            digits = fractionDigits(candidate)
        }
        candidate = fraction
        digits = fractionDigits(candidate)
        for _ in 0..<10 {
            if let parsed = Double("0.\(digits)"), wholeSeconds + parsed == timestamp {
                return String(base.dropLast()) + ".\(digits)Z"
            }
            candidate = candidate.nextDown
            digits = fractionDigits(candidate)
        }
        return String(base.dropLast()) + ".\(fractionDigits(fraction))Z"
    }

    private static func fractionDigits(_ fraction: Double) -> String {
        let value = String(format: "%.17f", locale: Locale(identifier: "en_US_POSIX"), fraction)
        return String(value.dropFirst(2))
    }

    private static func iso8601Date(from value: String) -> Date? {
        guard let dot = value.lastIndex(of: "."), value.last == "Z" else {
            return dateFormatter.value.date(from: value)
        }
        let fractionEnd = value.index(before: value.endIndex)
        let digits = String(value[value.index(after: dot)..<fractionEnd])
        guard !digits.isEmpty,
              digits.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
              let fraction = Double("0.\(digits)") else {
            return nil
        }
        let base = String(value[..<dot]) + "Z"
        guard let wholeDate = dateFormatter.value.date(from: base) else { return nil }
        return Date(timeIntervalSinceReferenceDate: wholeDate.timeIntervalSinceReferenceDate + fraction)
    }

    private func write(_ data: Data, to url: URL) throws {
        guard !hasSymbolicLinkBelowRoot(url) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try createDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func createDirectory(_ url: URL) throws {
        guard !hasSymbolicLinkBelowRoot(url) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        var current = url.standardizedFileURL
        let root = rootURL.standardizedFileURL
        while current.path == root.path || current.path.hasPrefix(root.path + "/") {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: current.path)
            guard current.path != root.path else { break }
            current.deleteLastPathComponent()
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isDirectory(_ url: URL) -> Bool {
        guard !isSymbolicLink(url) else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func hasSymbolicLinkBelowRoot(_ url: URL) -> Bool {
        let root = rootURL.standardizedFileURL
        let candidate = url.standardizedFileURL
        let rootPath = root.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else { return true }
        if isSymbolicLink(root) { return true }
        let relative = String(candidatePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return false }
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            if isSymbolicLink(current) { return true }
        }
        return false
    }

    private func directories(in url: URL) -> [URL] {
        guard isDirectory(url), let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        return children.filter { isDirectory($0) }
    }

    private func backupSources(pairID: UUID) -> [(source: URL, relativePath: String)] {
        var sources: [(source: URL, relativePath: String)] = [
            (rootURL.appendingPathComponent("pairs.json"), "pairs.json")
        ]
        let pairDirectory = self.pairDirectory(pairID)
        sources.append(contentsOf: Self.metadataFileNames.map {
            (pairDirectory.appendingPathComponent($0), $0)
        })

        let operations = pairDirectory.appendingPathComponent("operations", isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(at: operations, includingPropertiesForKeys: nil) {
            sources.append(contentsOf: files
                .filter { $0.pathExtension == "json" }
                .map { ($0, "operations/\($0.lastPathComponent)") })
        }
        return sources
    }

    private func backupSources(in backupDirectory: URL) -> [(source: URL, relativePath: String)] {
        var sources: [(source: URL, relativePath: String)] = []
        if let files = try? fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil) {
            sources.append(contentsOf: files
                .filter { $0.pathExtension == "json" }
                .map { ($0, $0.lastPathComponent) })
            let operations = backupDirectory.appendingPathComponent("operations", isDirectory: true)
            if let operationFiles = try? fileManager.contentsOfDirectory(at: operations, includingPropertiesForKeys: nil) {
                sources.append(contentsOf: operationFiles
                    .filter { $0.pathExtension == "json" }
                    .map { ($0, "operations/\($0.lastPathComponent)") })
            }
        }
        return sources
    }

    private func latestBackupDirectory(pairID: UUID) -> URL? {
        directories(in: pairDirectory(pairID).appendingPathComponent("backups", isDirectory: true))
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    private func latestBackupData(document: String, pairID: UUID?) -> Data? {
        let backupDirectories: [URL]
        if let pairID {
            backupDirectories = directories(in: pairDirectory(pairID).appendingPathComponent("backups", isDirectory: true))
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } else {
            let pairDirectories = directories(in: rootURL).filter { UUID(uuidString: $0.lastPathComponent) != nil }
            backupDirectories = pairDirectories.flatMap {
                directories(in: $0.appendingPathComponent("backups", isDirectory: true))
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }

        for backupDirectory in backupDirectories {
            let source = backupDirectory.appendingPathComponent(document)
            guard !isSymbolicLink(source), fileManager.fileExists(atPath: source.path) else { continue }
            if let data = try? Data(contentsOf: source) { return data }
        }
        return nil
    }

    private func moveAside(_ url: URL) {
        let stamp = Self.backupDateFormatter.value.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension()
        var destination = base.appendingPathExtension("corrupt-\(stamp).json")
        var suffix = 1
        while isSymbolicLink(destination) || fileManager.fileExists(atPath: destination.path) {
            destination = base.appendingPathExtension("corrupt-\(stamp)-\(suffix).json")
            suffix += 1
        }
        try? fileManager.moveItem(at: url, to: destination)
    }

    private func recordIssue(document: String, detail: String, recoveredFromBackup: Bool) {
        issueList.append(DevStateStoreIssue(
            document: document,
            detail: detail,
            occurredAt: Date(),
            recoveredFromBackup: recoveredFromBackup
        ))
        Task { @MainActor in
            LogManager.shared.warning("State document issue: \(document)", source: "DevSync")
        }
    }
}
