//
//  BookmarkManager.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation
import Combine

@MainActor
class BookmarkManager: ObservableObject {
    @Published var bookmarks: [CCSession] = []
    
    private let maxBookmarks = 5
    private let userDefaultsKey = "cchistory.bookmarks"
    
    init() {
        loadBookmarks()
    }
    
    // MARK: - Public Methods
    
    func addBookmark(_ session: CCSession) {
        // Don't add duplicates
        guard !isBookmarked(session) else { return }
        
        // Remove oldest if at capacity
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
    
    // MARK: - Persistence
    
    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([CCSession].self, from: data) else {
            return
        }
        
        // Filter out bookmarks whose files no longer exist
        bookmarks = decoded.filter { FileManager.default.fileExists(atPath: $0.filePath.path) }
    }
    
    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
