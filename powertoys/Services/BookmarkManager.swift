//
//  BookmarkManager.swift
//  powertoys
//

import Foundation

@Observable
@MainActor
final class BookmarkManager {
    var bookmarks: [CCSession] = []
    var bookmarksWithUpdates: Set<String> = []

    private let maxBookmarks = 5
    private let userDefaultsKey = "cchistory.bookmarks"

    init() {
        loadBookmarks()
    }
    
    // MARK: - Public Methods
    
    func addBookmark(_ session: CCSession) {
        guard !isBookmarked(session) else { return }
        
        if bookmarks.count >= maxBookmarks {
            bookmarks.removeFirst()
        }
        
        bookmarks.append(session)
        saveBookmarks()
    }
    
    func removeBookmark(_ session: CCSession) {
        bookmarks.removeAll { $0.id == session.id }
        saveBookmarks()
    }
    
    func isBookmarked(_ session: CCSession) -> Bool {
        bookmarks.contains { $0.id == session.id }
    }
    
    func toggleBookmark(_ session: CCSession) {
        if isBookmarked(session) {
            removeBookmark(session)
        } else {
            addBookmark(session)
        }
    }

    func markAsUpdated(_ sessionId: String) {
        if bookmarks.contains(where: { $0.id == sessionId }) {
            bookmarksWithUpdates.insert(sessionId)
        }
    }

    func clearUpdateMark(_ sessionId: String) {
        bookmarksWithUpdates.remove(sessionId)
    }

    func hasUpdate(_ sessionId: String) -> Bool {
        bookmarksWithUpdates.contains(sessionId)
    }
    
    // MARK: - Persistence
    
    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([CCSession].self, from: data) else {
            return
        }
        
        bookmarks = decoded.filter { FileManager.default.fileExists(atPath: $0.filePath.path) }
    }
    
    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
