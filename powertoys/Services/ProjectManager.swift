//
//  ProjectManager.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation
import Combine

@MainActor
class ProjectManager: ObservableObject {
    @Published var projects: [CCProject] = []
    @Published var isLoading: Bool = false
    @Published var selectedSession: CCSession?
    @Published var currentMessages: [CCMessage] = []
    
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var monitoredDirectory: Int32 = -1
    private let claudeDirectory: URL
    private var refreshTask: Task<Void, Never>?
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDirectory = home.appendingPathComponent(".claude/projects")
    }
    
    // MARK: - Project Loading
    
    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }
        
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: claudeDirectory.path) else {
            projects = []
            return
        }
        
        do {
            let projectFolders = try fileManager.contentsOfDirectory(
                at: claudeDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            var loadedProjects: [CCProject] = []
            
            for folder in projectFolders {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir),
                      isDir.boolValue else {
                    continue
                }
                
                let sessions = await loadSessions(in: folder)
                if !sessions.isEmpty {
                    let project = CCProject(folderName: folder.lastPathComponent, sessions: sessions)
                    loadedProjects.append(project)
                }
            }
            
            // Sort projects by most recent session
            loadedProjects.sort { p1, p2 in
                let t1 = p1.sessions.first?.timestamp ?? .distantPast
                let t2 = p2.sessions.first?.timestamp ?? .distantPast
                return t1 > t2
            }
            
            projects = loadedProjects
        } catch {
            print("Error loading projects: \(error)")
            projects = []
        }
    }
    
    private func loadSessions(in projectFolder: URL) async -> [CCSession] {
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
            
            // Sort by date (recent first)
            sessions.sort { s1, s2 in
                (s1.timestamp ?? .distantPast) > (s2.timestamp ?? .distantPast)
            }
            
            return sessions
        } catch {
            print("Error loading sessions from \(projectFolder): \(error)")
            return []
        }
    }
    
    // MARK: - Session Loading
    
    func loadMessages(for session: CCSession) async {
        selectedSession = session
        currentMessages = CCHistoryParser.parseJSONLFile(at: session.filePath)
    }
    
    // MARK: - File Watching
    
    func startWatching() {
        stopWatching()
        
        monitoredDirectory = open(claudeDirectory.path, O_EVTONLY)
        guard monitoredDirectory >= 0 else { return }
        
        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: monitoredDirectory,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        
        fileMonitor?.setEventHandler { [weak self] in
            self?.handleFileChange()
        }
        
        fileMonitor?.setCancelHandler { [weak self] in
            if let fd = self?.monitoredDirectory, fd >= 0 {
                close(fd)
            }
        }
        
        fileMonitor?.resume()
    }
    
    func stopWatching() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }
    
    private func handleFileChange() {
        // Debounce refresh
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            guard !Task.isCancelled else { return }
            await loadProjects()
            
            // Reload current session if still selected
            if let session = selectedSession {
                await loadMessages(for: session)
            }
        }
    }
    
    // MARK: - Search
    
    func searchGlobally(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
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
