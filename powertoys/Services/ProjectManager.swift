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
    var projects: [CCProject] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedSession: CCSession?
    var currentMessages: [CCMessage] = []
    var isLoadingMessages: Bool = false

    private var fileWatcher: FileWatcher?
    private let claudeDirectory: URL
    private var loadTask: Task<Void, Never>?
    private var messageLoadTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDirectory = home.appendingPathComponent(".claude/projects")
    }

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

        loadingProgress = 0.3

        var loadedProjects: [CCProject] = []
        let totalFolders = projectFolders.count

        for (index, folder) in projectFolders.enumerated() {
            let sessions = await loadSessionsLazy(in: folder)
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

        await SessionMetadataCache.shared.saveCache()

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
        let projectPath = projectFolder.lastPathComponent

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
                let parsedMetadata = await Task.detached(priority: .utility) {
                    CCHistoryParser.parseSessionMetadata(at: fileInfo.url)
                }.value

                let metadata = SessionMetadata(
                    sessionId: sessionId,
                    projectPath: projectPath,
                    firstUserMessage: parsedMetadata.firstUserMessage,
                    fileModificationDate: fileInfo.modDate,
                    messageCount: parsedMetadata.messageCount
                )
                await SessionMetadataCache.shared.set(metadata)

                let session = CCSession(
                    id: sessionId,
                    filePath: fileInfo.url,
                    firstUserMessage: parsedMetadata.firstUserMessage,
                    timestamp: parsedMetadata.timestamp ?? fileInfo.modDate,
                    messageCount: parsedMetadata.messageCount
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

    private nonisolated static func extractFirstUserMessage(from url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }

        guard let chunk = try? handle.read(upToCount: 8192) else { return nil }
        guard let content = String(data: chunk, encoding: .utf8) else { return nil }

        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user" else {
                continue
            }

            if let message = json["message"] as? [String: Any] {
                if let text = message["content"] as? String {
                    return String(text.prefix(100))
                }
                if let contentArray = message["content"] as? [[String: Any]] {
                    for item in contentArray {
                        if let itemType = item["type"] as? String, itemType == "text",
                           let text = item["text"] as? String {
                            return String(text.prefix(100))
                        }
                    }
                }
            }

            if let text = json["content"] as? String {
                return String(text.prefix(100))
            }
        }

        return nil
    }

    // MARK: - Message Loading

    func loadMessages(for session: CCSession) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        messageLoadTask?.cancel()
        selectedSession = session
        currentMessages = []
        isLoadingMessages = true

        LogManager.shared.debug("Loading messages for \(session.id)...", source: "ProjectManager")

        let filePath = session.filePath
        let messages = await Task.detached(priority: .userInitiated) {
            CCHistoryParser.parseJSONLFile(at: filePath)
        }.value

        guard !Task.isCancelled else { return }

        currentMessages = messages
        isLoadingMessages = false

        // Update session message count in project
        if session.messageCount != messages.count {
            for projectIndex in projects.indices {
                if let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == session.id }) {
                    projects[projectIndex].sessions[sessionIndex].messageCount = messages.count
                }
            }
            selectedSession?.messageCount = messages.count
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        LogManager.shared.debug("Loaded \(messages.count) messages in \(String(format: "%.2f", elapsed))s", source: "ProjectManager")
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()
        fileWatcher = FileWatcher(path: claudeDirectory.path, latency: 1.0) { [weak self] changedPaths in
            guard let self else { return }
            Task { @MainActor in
                self.handleFileChange(changedPaths: changedPaths)
            }
        }
        fileWatcher?.start()
    }

    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func handleFileChange(changedPaths: [String]) {
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await loadProjects()

            if let session = selectedSession,
               changedPaths.contains(session.filePath.path) {
                await loadMessages(for: session)
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
