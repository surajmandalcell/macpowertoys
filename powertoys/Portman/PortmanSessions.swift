import Darwin
import Foundation

nonisolated struct PortmanSession: Sendable {
    enum Kind: Sendable { case claude, codex }

    let kind: Kind
    let id: UUID

    var label: String {
        switch kind {
        case .claude: "Claude Code"
        case .codex: "Codex · folder match"
        }
    }

    var resumeCommand: String {
        switch kind {
        case .claude: "claude --resume \(id.uuidString.lowercased())"
        case .codex: "codex resume \(id.uuidString.lowercased())"
        }
    }
}

actor PortmanSessionResolver {
    static let shared = PortmanSessionResolver()

    private var codexIndex: [String: (session: PortmanSession, modified: Date)] = [:]
    private var indexedAt = Date.distantPast

    func resolve(pid: Int32, started: UInt64, userID: UInt32, folder: String) -> PortmanSession? {
        if let id = Self.claudeSessionID(pid: pid, started: started, userID: userID, folder: folder) {
            return PortmanSession(kind: .claude, id: id)
        }
        guard folder.hasPrefix(NSHomeDirectory() + "/") else { return nil }
        if Date().timeIntervalSince(indexedAt) > 60 { refreshCodexIndex() }
        var path = folder
        while path.count > NSHomeDirectory().count {
            if let match = codexIndex[path] { return match.session }
            path = (path as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func claudeSessionID(pid: Int32, started: UInt64, userID: UInt32, folder: String) -> UUID? {
        let launch = PortmanLaunch.inspect(pid: pid, started: started,
                                           userID: userID, folder: folder)
        return launch?.environment["CLAUDE_CODE_SESSION_ID"].flatMap(UUID.init(uuidString:))
    }

    nonisolated static func sessionID(in bytes: [UInt8]) -> UUID? {
        PortmanLaunch.parse(bytes, folder: "/")?.environment["CLAUDE_CODE_SESSION_ID"]
            .flatMap(UUID.init(uuidString:))
    }

    private func refreshCodexIndex() {
        indexedAt = Date()
        var next: [String: (session: PortmanSession, modified: Date)] = [:]
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        let cutoff = Date().addingTimeInterval(-3 * 24 * 3_600)
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { codexIndex = [:]; return }
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, modified > cutoff,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let data = (try? handle.read(upToCount: 16_384)) ?? Data()
            try? handle.close()
            guard let first = String(decoding: data, as: UTF8.self).split(separator: "\n").first,
                  let object = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let directory = payload["cwd"] as? String,
                  let rawID = payload["id"] as? String,
                  let id = UUID(uuidString: rawID),
                  (next[directory]?.modified ?? .distantPast) < modified else { continue }
            next[directory] = (PortmanSession(kind: .codex, id: id), modified)
        }
        codexIndex = next
    }
}
