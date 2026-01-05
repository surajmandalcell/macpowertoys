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

    func loadProjectsInBackground() {
        loadTask?.cancel()
        loadTask = Task {
            await loadProjects()
        }
    }

    func loadProjects() async {
        isLoading = true
        loadingProgress = 0

        let directory = claudeDirectory

        let stream = AsyncStream<(CCProject, Double)> { continuation in
            Task.detached(priority: .userInitiated) {
                await Self.loadProjectsWithProgress(directory: directory) { project, progress in
                    continuation.yield((project, progress))
                }
                continuation.finish()
            }
        }

        var loadedProjects: [CCProject] = []

        for await (project, progress) in stream {
            guard !Task.isCancelled else { return }
            loadedProjects.append(project)
            loadingProgress = progress
        }

        loadedProjects.sort { p1, p2 in
            let t1 = p1.sessions.first?.timestamp ?? .distantPast
            let t2 = p2.sessions.first?.timestamp ?? .distantPast
            return t1 > t2
        }

        projects = loadedProjects
        isLoading = false
        loadingProgress = 1.0
    }

    private static func loadProjectsWithProgress(
        directory: URL,
        onProject: @Sendable (CCProject, Double) -> Void
    ) async {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else { return }

        do {
            let projectFolders = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }

            let total = Double(projectFolders.count)

            for (index, folder) in projectFolders.enumerated() {
                let sessions = loadSessionsSync(in: folder)
                if !sessions.isEmpty {
                    let project = CCProject(folderName: folder.lastPathComponent, sessions: sessions)
                    let progress = Double(index + 1) / max(total, 1)
                    onProject(project, progress)
                }
            }
        } catch {
            // Silently fail
        }
    }

    private static func loadSessionsSync(in projectFolder: URL) -> [CCSession] {
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(
                at: projectFolder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            var sessions: [CCSession] = []

            for file in files where file.pathExtension == "jsonl" {
                let sessionId = file.deletingPathExtension().lastPathComponent
                let metadata = CCHistoryParser.parseSessionMetadata(at: file)

                let session = CCSession(
                    id: sessionId,
                    filePath: file,
                    firstUserMessage: metadata.firstUserMessage,
                    timestamp: metadata.timestamp,
                    messageCount: metadata.messageCount
                )
                sessions.append(session)
            }

            sessions.sort { s1, s2 in
                (s1.timestamp ?? .distantPast) > (s2.timestamp ?? .distantPast)
            }

            return sessions
        } catch {
            return []
        }
    }
    
    // MARK: - Session Loading

    private var messageLoadTask: Task<Void, Never>?

    func loadMessages(for session: CCSession) async {
        messageLoadTask?.cancel()
        selectedSession = session
        currentMessages = []
        isLoadingMessages = true

        if let cachedMessages = cacheService.getCachedMessages(sessionId: session.id, filePath: session.filePath) {
            currentMessages = cachedMessages
            isLoadingMessages = false
            LogManager.shared.debug("Cache hit for session \(session.id)", source: "ProjectManager")
            return
        }

        LogManager.shared.debug("Cache miss for session \(session.id), streaming parse", source: "ProjectManager")

        let filePath = session.filePath
        let sessionId = session.id
        let projectPath = filePath.deletingLastPathComponent().lastPathComponent

        messageLoadTask = Task {
            var allMessages: [CCMessage] = []
            let stream = CCHistoryParser.parseJSONLFileStreaming(at: filePath)

            for await message in stream {
                guard !Task.isCancelled else { return }
                allMessages.append(message)
                await MainActor.run {
                    self.currentMessages.append(message)
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.cacheService.cacheConversation(
                    sessionId: sessionId,
                    projectPath: projectPath,
                    filePath: filePath,
                    messages: allMessages
                )
                self.isLoadingMessages = false
            }
        }
        await messageLoadTask?.value
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

    func searchGlobally(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let currentProjects = projects
        let results = await Task.detached(priority: .userInitiated) {
            Self.performSearch(query: query, in: currentProjects)
        }.value

        return results
    }

    private nonisolated static func performSearch(query: String, in projects: [CCProject]) -> [SearchResult] {
        let lowercasedQuery = query.lowercased()
        var results: [SearchResult] = []

        for project in projects {
            for session in project.sessions {
                let messages = CCHistoryParser.parseJSONLFile(at: session.filePath)
                let matchingMessages = messages.filter { message in
                    message.content.lowercased().contains(lowercasedQuery)
                }

                if !matchingMessages.isEmpty {
                    let preview = matchingMessages.first?.content.prefix(100) ?? ""
                    let result = SearchResult(
                        id: session.id,
                        project: project,
                        session: session,
                        matchingMessages: matchingMessages,
                        preview: String(preview)
                    )
                    results.append(result)
                }
            }
        }

        return results
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
