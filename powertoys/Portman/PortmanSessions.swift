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
        if let id = Self.claudeSessionID(pid: pid, started: started, userID: userID) {
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

    private static func claudeSessionID(pid: Int32, started: UInt64, userID: UInt32) -> UUID? {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
              info.pbi_uid == userID,
              info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec == started else { return nil }

        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(argMax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = bytes.count
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        return sessionID(in: Array(bytes.prefix(size)))
    }

    nonisolated static func sessionID(in bytes: [UInt8]) -> UUID? {
        guard bytes.count >= 4 else { return nil }
        let count = bytes.prefix(4).enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << ($1.offset * 8))
        }
        guard count <= 1_024 else { return nil }
        var index = 4
        func read() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            guard index < bytes.count else { return nil }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return text
        }
        guard read() != nil else { return nil } // executable path
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        for _ in 0..<count { guard read() != nil else { return nil } }
        while let entry = read() {
            if entry.hasPrefix("CLAUDE_CODE_SESSION_ID=") {
                return UUID(uuidString: String(entry.dropFirst("CLAUDE_CODE_SESSION_ID=".count)))
            }
        }
        return nil
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
