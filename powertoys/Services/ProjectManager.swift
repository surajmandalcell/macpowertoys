//
//  ProjectManager.swift
//  powertoys
//
//  Lazy-loading project manager. Projects load instantly from folder names.
//  Sessions load when expanded. Messages load when selected.
//

import Foundation

@Observable
@MainActor
final class ProjectManager {
    static weak var current: ProjectManager?
    var projects: [CCProject] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedSession: CCSession?
    var currentMessages: [CCMessage] = []
    var isLoadingMessages: Bool = false
    var recentlyUpdatedSessionIds: Set<String> = []

    private var fileWatcher: FileWatcher?
    private let claudeDirectory: URL
    private var loadTask: Task<Void, Never>?
    private var messageLoadTask: Task<[CCMessage], Never>?
    private var messageLoadGeneration = UUID()
    private var updateClearTasks: [String: Task<Void, Never>] = [:]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDirectory = home.appendingPathComponent(".claude/projects")
        Self.current = self
    }

    var fileWatcherOwnerCount: Int { fileWatcher == nil ? 0 : 1 }

    // MARK: - Project Loading (Instant)

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

        await SessionMetadataCache.shared.loadCache()
        loadingProgress = 0.1

        let directory = claudeDirectory
        let projectFolders = await Task.detached(priority: .userInitiated) {
            Self.getProjectFolders(in: directory)
        }.value
        guard !Task.isCancelled else { return }

        loadingProgress = 0.3

        var loadedProjects: [CCProject] = []
        let totalFolders = projectFolders.count

        for (index, folder) in projectFolders.enumerated() {
            let sessions = await loadSessionsLazy(in: folder)
            guard !Task.isCancelled else { return }
            if !sessions.isEmpty {
                let project = CCProject(folderName: folder.lastPathComponent, sessions: sessions)
                loadedProjects.append(project)
            }
            loadingProgress = 0.3 + (0.6 * Double(index + 1) / Double(totalFolders))
        }

        loadedProjects.sort { p1, p2 in
            let t1 = p1.sessions.first?.timestamp ?? .distantPast
            let t2 = p2.sessions.first?.timestamp ?? .distantPast
            return t1 > t2
        }

        projects = loadedProjects
        isLoading = false
        loadingProgress = 1.0

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        LogManager.shared.info("Project load complete: \(loadedProjects.count) projects in \(String(format: "%.2f", elapsed))s", source: "ProjectManager")
    }

    private nonisolated static func getProjectFolders(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
        } catch {
            return []
        }
    }

    // MARK: - Session Loading (Lazy)

    private func loadSessionsLazy(in projectFolder: URL) async -> [CCSession] {
        let fileInfos = await Task.detached(priority: .userInitiated) {
            Self.getSessionFiles(in: projectFolder)
        }.value

        var sessions: [CCSession] = []

        for fileInfo in fileInfos {
            let sessionId = fileInfo.url.deletingPathExtension().lastPathComponent

            let cached = await SessionMetadataCache.shared.get(sessionId)
            if let cached = cached, await SessionMetadataCache.shared.isValid(sessionId, fileModDate: fileInfo.modDate) {
                let session = CCSession(
                    id: sessionId,
                    filePath: fileInfo.url,
                    firstUserMessage: cached.firstUserMessage,
                    timestamp: cached.fileModificationDate,
                    messageCount: cached.messageCount ?? 0
                )
                sessions.append(session)
            } else {
                let quickMetadata = await Task.detached(priority: .utility) {
                    CCHistoryParser.parseSessionMetadataQuick(at: fileInfo.url)
                }.value

                let session = CCSession(
                    id: sessionId,
                    filePath: fileInfo.url,
                    firstUserMessage: quickMetadata.firstUserMessage,
                    timestamp: quickMetadata.timestamp ?? fileInfo.modDate,
                    messageCount: 0
                )
                sessions.append(session)
            }
        }

        sessions.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        return sessions
    }

    private nonisolated static func getSessionFiles(in folder: URL) -> [(url: URL, modDate: Date)] {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            return files.compactMap { file -> (URL, Date)? in
                guard file.pathExtension == "jsonl" else { return nil }
                let attrs = try? fileManager.attributesOfItem(atPath: file.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                return (file, modDate)
            }
        } catch {
            return []
        }
    }

    // MARK: - Message Loading

    func loadMessages(for session: CCSession, isRefresh: Bool = false) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        messageLoadTask?.cancel()
        let generation = UUID()
        messageLoadGeneration = generation

        let isSameSession = selectedSession?.id == session.id
        if !isSameSession {
            selectedSession = session
            currentMessages = []
            isLoadingMessages = true
        } else if !isRefresh {
            isLoadingMessages = true
        }

        LogManager.shared.debug("Loading messages for \(session.id) (refresh: \(isRefresh), same: \(isSameSession))...", source: "ProjectManager")

        let filePath = session.filePath
        let task = Task.detached(priority: .userInitiated) {
            CCHistoryParser.parseJSONLFile(at: filePath)
        }
        messageLoadTask = task
        let messages = await task.value

        guard !task.isCancelled, messageLoadGeneration == generation else { return }
        messageLoadTask = nil

        if isSameSession && isRefresh {
            let existingIds = Set(currentMessages.map(\.id))
            let newMessages = messages.filter { !existingIds.contains($0.id) }
            if !newMessages.isEmpty {
                currentMessages.append(contentsOf: newMessages)
                LogManager.shared.debug("Appended \(newMessages.count) new messages", source: "ProjectManager")
            }
            for (index, msg) in currentMessages.enumerated() {
                if let updated = messages.first(where: { $0.id == msg.id }), updated.content != msg.content {
                    currentMessages[index] = updated
                }
            }
        } else {
            currentMessages = messages
        }
        isLoadingMessages = false
        selectedSession = session

        if session.messageCount != messages.count {
            for projectIndex in projects.indices {
                if let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == session.id }) {
                    var updatedSession = projects[projectIndex].sessions[sessionIndex]
                    updatedSession.messageCount = messages.count

                    var updatedProject = projects[projectIndex]
                    updatedProject.sessions[sessionIndex] = updatedSession
                    projects[projectIndex] = updatedProject

                    let metadata = SessionMetadata(
                        sessionId: session.id,
                        projectPath: updatedProject.id,
                        firstUserMessage: updatedSession.firstUserMessage,
                        fileModificationDate: updatedSession.timestamp ?? Date(),
                        messageCount: messages.count
                    )
                    Task {
                        await SessionMetadataCache.shared.set(metadata)
                        await SessionMetadataCache.shared.saveCache()
                    }

                    selectedSession = updatedSession
                    break
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        LogManager.shared.debug("Loaded \(messages.count) messages in \(String(format: "%.2f", elapsed))s", source: "ProjectManager")
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()
        fileWatcher = FileWatcher(path: claudeDirectory.path, latency: 1.0) { [weak self] changes in
            guard let self else { return }
            Task { @MainActor in
                self.handleFileChange(changedPaths: changes.map(\.path))
            }
        }
        fileWatcher?.start()
    }

    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
        loadTask?.cancel()
        loadTask = nil
        messageLoadTask?.cancel()
        messageLoadTask = nil
        messageLoadGeneration = UUID()
        updateClearTasks.values.forEach { $0.cancel() }
        updateClearTasks.removeAll()
        recentlyUpdatedSessionIds.removeAll()
        isLoading = false
        isLoadingMessages = false
    }

    private func handleFileChange(changedPaths: [String]) {
        let changedSessionIds = findChangedSessionIds(from: changedPaths)
        for sessionId in changedSessionIds {
            markSessionAsUpdated(sessionId)
        }

        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let currentSessionId = selectedSession?.id
            let currentSessionPath = selectedSession?.filePath

            await loadProjects()

            if let sessionId = currentSessionId, let sessionPath = currentSessionPath {
                let sessionFileName = sessionPath.lastPathComponent
                let normalizedSessionPath = sessionPath.standardizedFileURL.path.lowercased()

                let shouldRefresh = changedPaths.contains { path in
                    let normalizedChangedPath = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
                    return normalizedChangedPath == normalizedSessionPath ||
                           path.hasSuffix("/\(sessionFileName)") ||
                           normalizedChangedPath.contains(sessionFileName.lowercased())
                }

                if shouldRefresh {
                    LogManager.shared.debug("File change detected for session \(sessionId), refreshing", source: "ProjectManager")
                    if let updatedSession = projects.flatMap({ $0.sessions }).first(where: { $0.id == sessionId }) {
                        await loadMessages(for: updatedSession, isRefresh: true)
                    }
                }
            }
        }
    }

    private func findChangedSessionIds(from paths: [String]) -> [String] {
        var sessionIds: [String] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "jsonl" {
                let sessionId = url.deletingPathExtension().lastPathComponent
                sessionIds.append(sessionId)
            }
        }
        return sessionIds
    }

    private func markSessionAsUpdated(_ sessionId: String) {
        recentlyUpdatedSessionIds.insert(sessionId)

        updateClearTasks[sessionId]?.cancel()
        updateClearTasks[sessionId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.recentlyUpdatedSessionIds.remove(sessionId)
            self?.updateClearTasks[sessionId] = nil
        }
    }

    func isSessionActive(_ sessionId: String) -> Bool {
        recentlyUpdatedSessionIds.contains(sessionId)
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

    func searchGlobally(query: String, deepSearch: Bool = false) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        if deepSearch {
            return await searchSessionsDeep(query: query)
        }
        return searchSessions(query: query)
    }

    private func searchSessionsDeep(query: String) async -> [SearchResult] {
        let lowercasedQuery = query.lowercased()

        return await Task.detached(priority: .userInitiated) { [projects] in
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
                            preview: session.firstUserMessage ?? session.id,
                            isContentMatch: false
                        )
                        results.append(result)
                    } else if CCHistoryParser.containsContent(at: session.filePath, query: query) {
                        let previews = CCHistoryParser.searchContent(at: session.filePath, query: query, maxMatches: 1)
                        let result = SearchResult(
                            id: session.id,
                            project: project,
                            session: session,
                            matchingMessages: [],
                            preview: previews.first ?? session.firstUserMessage ?? session.id,
                            isContentMatch: true
                        )
                        results.append(result)
                    }
                }
            }

            return results
        }.value
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id: String
    let project: CCProject
    let session: CCSession
    let matchingMessages: [CCMessage]
    let preview: String
    var isContentMatch: Bool = false
}
