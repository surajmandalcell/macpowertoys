//
//  ProjectManager.swift
//  powertoys
//

import Foundation

@Observable
@MainActor
final class ProjectManager {
    var projects: [CCProject] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedSession: CCSession?
    var currentMessages: [CCMessage] = []
    var isLoadingMessages: Bool = false

    private var fileWatcher: FileWatcher?
    private let claudeDirectory: URL
    private var refreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private let cacheService = ConversationCacheService.shared

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDirectory = home.appendingPathComponent(".claude/projects")
    }

    struct CachedMetadataSnapshot: Sendable {
        let projectPath: String
        let filePath: String
        let fileModificationDate: Date
        let firstUserMessage: String?
        let messageCount: Int
        let timestamp: Date?
    }

    struct CacheUpdate: Sendable {
        let sessionId: String
        let projectPath: String
        let filePath: String
        let fileModificationDate: Date
        let firstUserMessage: String?
        let messageCount: Int
        let timestamp: Date?
    }

    struct LoadResult: Sendable {
        let projects: [CCProject]
        let cacheUpdates: [CacheUpdate]
    }

    func loadProjectsInBackground() {
        loadTask?.cancel()
        loadTask = Task {
            await loadProjects()
        }
    }

    func loadProjects() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        isLoading = true
        loadingProgress = 0

        LogManager.shared.info("Starting project load...", source: "ProjectManager")

        let cachedMetadata = cacheService.getAllCachedMetadata()
        if !cachedMetadata.isEmpty {
            let cacheLoadStart = CFAbsoluteTimeGetCurrent()
            let cachedProjects = buildProjectsFromMetadataCache(cachedMetadata)
            projects = cachedProjects
            loadingProgress = 0.3
            let cacheElapsed = CFAbsoluteTimeGetCurrent() - cacheLoadStart
            LogManager.shared.info("Loaded \(cachedMetadata.count) sessions from cache in \(String(format: "%.3f", cacheElapsed))s", source: "ProjectManager")
        }

        let directory = claudeDirectory
        let existingCache = cachedMetadata.reduce(into: [String: CachedMetadataSnapshot]()) { dict, meta in
            dict[meta.sessionId] = CachedMetadataSnapshot(
                projectPath: meta.projectPath,
                filePath: meta.filePath,
                fileModificationDate: meta.fileModificationDate,
                firstUserMessage: meta.firstUserMessage,
                messageCount: meta.messageCount,
                timestamp: meta.timestamp
            )
        }

        let loadResult = await Task.detached(priority: .userInitiated) {
            await Self.loadAllProjectsOffMainThread(directory: directory, existingCache: existingCache)
        }.value

        let sortedProjects = loadResult.projects.sorted { p1, p2 in
            let t1 = p1.sessions.first?.timestamp ?? .distantPast
            let t2 = p2.sessions.first?.timestamp ?? .distantPast
            return t1 > t2
        }

        projects = sortedProjects
        isLoading = false
        loadingProgress = 1.0

        for update in loadResult.cacheUpdates {
            cacheService.cacheMetadata(
                sessionId: update.sessionId,
                projectPath: update.projectPath,
                filePath: URL(fileURLWithPath: update.filePath),
                fileModDate: update.fileModificationDate,
                firstUserMessage: update.firstUserMessage,
                messageCount: update.messageCount,
                timestamp: update.timestamp
            )
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        LogManager.shared.info("Project load complete: \(sortedProjects.count) projects in \(String(format: "%.2f", elapsed))s", source: "ProjectManager")
    }

    private func buildProjectsFromMetadataCache(_ metadata: [CachedSessionMetadata]) -> [CCProject] {
        var projectMap: [String: [CCSession]] = [:]

        for item in metadata {
            let session = CCSession(
                id: item.sessionId,
                filePath: URL(fileURLWithPath: item.filePath),
                firstUserMessage: item.firstUserMessage,
                timestamp: item.timestamp ?? item.fileModificationDate,
                messageCount: item.messageCount
            )

            projectMap[item.projectPath, default: []].append(session)
        }

        return projectMap.map { path, sessions in
            let sorted = sessions.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            return CCProject(folderName: path, sessions: sorted)
        }.sorted { p1, p2 in
            let t1 = p1.sessions.first?.timestamp ?? .distantPast
            let t2 = p2.sessions.first?.timestamp ?? .distantPast
            return t1 > t2
        }
    }

    private static func loadAllProjectsOffMainThread(
        directory: URL,
        existingCache: [String: CachedMetadataSnapshot]
    ) async -> LoadResult {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return LoadResult(projects: [], cacheUpdates: [])
        }

        do {
            let projectFolders = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }

            var allProjects: [CCProject] = []
            var allCacheUpdates: [CacheUpdate] = []

            for folder in projectFolders {
                let (sessions, updates) = loadSessionsOffMainThread(
                    in: folder,
                    existingCache: existingCache
                )
                if !sessions.isEmpty {
                    let project = CCProject(folderName: folder.lastPathComponent, sessions: sessions)
                    allProjects.append(project)
                }
                allCacheUpdates.append(contentsOf: updates)
            }

            return LoadResult(projects: allProjects, cacheUpdates: allCacheUpdates)
        } catch {
            return LoadResult(projects: [], cacheUpdates: [])
        }
    }

    private static func loadSessionsOffMainThread(
        in projectFolder: URL,
        existingCache: [String: CachedMetadataSnapshot]
    ) -> ([CCSession], [CacheUpdate]) {
        let fileManager = FileManager.default
        let projectPath = projectFolder.lastPathComponent

        do {
            let files = try fileManager.contentsOfDirectory(
                at: projectFolder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            var sessions: [CCSession] = []
            var cacheUpdates: [CacheUpdate] = []

            for file in files where file.pathExtension == "jsonl" {
                let sessionId = file.deletingPathExtension().lastPathComponent

                let attrs = try? fileManager.attributesOfItem(atPath: file.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()

                if let cached = existingCache[sessionId],
                   abs(cached.fileModificationDate.timeIntervalSince(modDate)) < 1.0 {
                    let session = CCSession(
                        id: sessionId,
                        filePath: file,
                        firstUserMessage: cached.firstUserMessage,
                        timestamp: cached.timestamp ?? cached.fileModificationDate,
                        messageCount: cached.messageCount
                    )
                    sessions.append(session)
                } else {
                    let metadata = parseMetadataFast(at: file)

                    let update = CacheUpdate(
                        sessionId: sessionId,
                        projectPath: projectPath,
                        filePath: file.path,
                        fileModificationDate: modDate,
                        firstUserMessage: metadata.firstUserMessage,
                        messageCount: metadata.messageCount,
                        timestamp: metadata.timestamp
                    )
                    cacheUpdates.append(update)

                    let session = CCSession(
                        id: sessionId,
                        filePath: file,
                        firstUserMessage: metadata.firstUserMessage,
                        timestamp: metadata.timestamp ?? modDate,
                        messageCount: metadata.messageCount
                    )
                    sessions.append(session)
                }
            }

            sessions.sort { s1, s2 in
                (s1.timestamp ?? .distantPast) > (s2.timestamp ?? .distantPast)
            }

            return (sessions, cacheUpdates)
        } catch {
            return ([], [])
        }
    }

    private static func parseMetadataFast(at url: URL) -> (firstUserMessage: String?, timestamp: Date?, messageCount: Int) {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            return (nil, nil, 0)
        }
        defer { try? handle.close() }

        var firstUserMessage: String?
        var latestTimestamp: Date?
        var messageCount = 0
        var buffer = Data()
        let chunkSize = 16384

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard !lineData.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String,
                      ["user", "assistant", "system"].contains(type) else {
                    continue
                }

                messageCount += 1

                if let timestampStr = json["timestamp"] as? String {
                    if let date = parseTimestampFast(timestampStr) {
                        if latestTimestamp == nil || date > latestTimestamp! {
                            latestTimestamp = date
                        }
                    }
                }

                if type == "user" && firstUserMessage == nil {
                    firstUserMessage = extractContentFast(from: json)
                }
            }
        }

        return (firstUserMessage, latestTimestamp, messageCount)
    }

    private static func extractContentFast(from json: [String: Any]) -> String {
        if let message = json["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                return String(content.prefix(100))
            }
            if let contentArray = message["content"] as? [[String: Any]] {
                for item in contentArray {
                    if let type = item["type"] as? String, type == "text",
                       let text = item["text"] as? String {
                        return String(text.prefix(100))
                    }
                }
            }
        }
        if let content = json["content"] as? String {
            return String(content.prefix(100))
        }
        return ""
    }

    private static func parseTimestampFast(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Session Loading

    private var messageLoadTask: Task<Void, Never>?

    func loadMessages(for session: CCSession) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        messageLoadTask?.cancel()
        selectedSession = session
        currentMessages = []
        isLoadingMessages = true

        if let cachedMessages = cacheService.getCachedMessages(sessionId: session.id, filePath: session.filePath) {
            currentMessages = cachedMessages
            isLoadingMessages = false
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            LogManager.shared.debug("Cache hit: \(cachedMessages.count) messages in \(String(format: "%.3f", elapsed))s", source: "ProjectManager")
            return
        }

        LogManager.shared.debug("Cache miss for \(session.id), parsing...", source: "ProjectManager")

        let filePath = session.filePath
        let sessionId = session.id
        let projectPath = filePath.deletingLastPathComponent().lastPathComponent

        let messages = await Task.detached(priority: .userInitiated) {
            CCHistoryParser.parseJSONLFile(at: filePath)
        }.value

        guard !Task.isCancelled else { return }

        currentMessages = messages
        isLoadingMessages = false

        cacheService.cacheConversation(
            sessionId: sessionId,
            projectPath: projectPath,
            filePath: filePath,
            messages: messages
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        LogManager.shared.debug("Parsed \(messages.count) messages in \(String(format: "%.2f", elapsed))s", source: "ProjectManager")
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()

        fileWatcher = FileWatcher(path: claudeDirectory.path, latency: 0.5) { [weak self] changedPaths in
            guard let self else { return }
            self.handleFileChange(changedPaths: changedPaths)
        }
        fileWatcher?.start()
    }

    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func handleFileChange(changedPaths: [String]) {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let jsonlPaths = changedPaths.filter { $0.hasSuffix(".jsonl") }

            for path in jsonlPaths {
                let sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                cacheService.invalidate(sessionId)
            }

            if jsonlPaths.isEmpty {
                await loadProjects()
            } else {
                await loadProjects()

                if let session = selectedSession,
                   jsonlPaths.contains(session.filePath.path) {
                    await loadMessages(for: session)
                }
            }
        }
    }

    // MARK: - Search

    func searchSessions(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let lowercasedQuery = query.lowercased()
        var results: [SearchResult] = []

        for project in projects {
            for session in project.sessions {
                let titleMatch = session.firstUserMessage?.lowercased().contains(lowercasedQuery) ?? false
                let idMatch = session.id.lowercased().contains(lowercasedQuery)
                let projectMatch = project.displayName.lowercased().contains(lowercasedQuery)

                if titleMatch || idMatch || projectMatch {
                    let result = SearchResult(
                        id: session.id,
                        project: project,
                        session: session,
                        matchingMessages: [],
                        preview: session.firstUserMessage ?? session.id
                    )
                    results.append(result)
                }
            }
        }

        return results
    }

    func searchGlobally(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        return searchSessions(query: query)
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id: String
    let project: CCProject
    let session: CCSession
    let matchingMessages: [CCMessage]
    let preview: String
}
