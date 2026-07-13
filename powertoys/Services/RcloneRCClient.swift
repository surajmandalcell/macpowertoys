//
//  RcloneRCClient.swift
//  powertoys
//

import Foundation

// MARK: - Response DTOs

struct JobStatusResult: Sendable {
    let finished: Bool
    let success: Bool
    let error: String
    let duration: Double
    let outputBytes: Int64?
    let outputCount: Int?
}

struct AboutResult: Sendable {
    let total: Int64?
    let used: Int64?
    let free: Int64?
}

struct RcloneRCCredentials: Sendable, Equatable {
    let username: String
    let password: String
}

struct RcloneOptionExample: Sendable, Equatable {
    let value: String
    let help: String
}

struct RcloneProviderOption: Sendable, Equatable, Identifiable {
    let name: String
    let fieldName: String
    let help: String
    let type: String
    let defaultValue: String
    let required: Bool
    let isPassword: Bool
    let advanced: Bool
    let hidden: Bool
    let exclusive: Bool
    let examples: [RcloneOptionExample]

    var id: String { fieldName.isEmpty ? name : fieldName }
    var label: String { name.replacingOccurrences(of: "_", with: " ").capitalized }
    var usesExclusivePicker: Bool { exclusive && !examples.isEmpty }
}

struct RcloneProvider: Sendable, Equatable, Identifiable {
    let name: String
    let description: String
    let prefix: String
    let options: [RcloneProviderOption]

    var id: String { name }
    var displayName: String { description.isEmpty ? name : description }
}

struct RcloneConfigurationStep: Sendable, Equatable {
    let state: String
    let option: RcloneProviderOption?
    let error: String

    var isComplete: Bool { state.isEmpty }
}

enum RcloneRCError: LocalizedError {
    case notReachable
    case http(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notReachable: return "The rclone daemon is not reachable."
        case .http(let status, let message): return message.isEmpty ? "rclone error (HTTP \(status))" : message
        case .decoding(let detail): return "Unexpected response from rclone: \(detail)"
        }
    }
}

// MARK: - RC Client

actor RcloneRCClient {
    private let baseURL: URL
    private let credentials: RcloneRCCredentials?
    private let session: URLSession

    init(port: Int, credentials: RcloneRCCredentials? = nil) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    init(baseURL: URL, credentials: RcloneRCCredentials? = nil, session: URLSession) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
    }

    // MARK: Core requests

    private func post(_ path: String, body: [String: Any], timeout: TimeInterval? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credentials {
            let token = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if let timeout {
            request.timeoutInterval = timeout
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw RcloneRCError.notReachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw RcloneRCError.notReachable
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard (200..<300).contains(http.statusCode) else {
            let message = (json["error"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
            throw RcloneRCError.http(status: http.statusCode, message: message)
        }

        return json
    }

    // MARK: Health / info

    func ping() async throws {
        _ = try await post("rc/noop", body: [:])
    }

    func version() async throws -> String {
        let json = try await post("core/version", body: [:])
        return (json["version"] as? String) ?? "unknown"
    }

    func listRemotes() async throws -> [String] {
        let json = try await post("config/listremotes", body: [:])
        return (json["remotes"] as? [String]) ?? []
    }

    func remoteTypes() async throws -> [String: String] {
        let json = try await post("config/dump", body: [:])
        var result: [String: String] = [:]
        for (name, value) in json {
            if let dict = value as? [String: Any], let type = dict["type"] as? String {
                result[name] = type
            }
        }
        return result
    }

    func providers() async throws -> [RcloneProvider] {
        let json = try await post("config/providers", body: [:], timeout: 60)
        guard let rawProviders = json["providers"] as? [[String: Any]] else {
            throw RcloneRCError.decoding("missing providers")
        }
        return rawProviders.compactMap(Self.parseProvider).sorted {
            let lhs = $0.description.isEmpty ? $0.name : $0.description
            let rhs = $1.description.isEmpty ? $1.name : $1.description
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    func about(fs: String) async throws -> AboutResult {
        let json = try await post("operations/about", body: ["fs": fs])
        func int(_ key: String) -> Int64? {
            if let n = json[key] as? Int64 { return n }
            if let n = json[key] as? Int { return Int64(n) }
            if let n = json[key] as? Double { return Int64(n) }
            return nil
        }
        return AboutResult(total: int("total"), used: int("used"), free: int("free"))
    }

    // MARK: Jobs

    func startJob(
        endpoint: String,
        srcFs: String,
        dstFs: String,
        group: String,
        excludePatterns: [String],
        config: [String: Any]
    ) async throws -> Int {
        var body: [String: Any] = [
            "srcFs": srcFs,
            "dstFs": dstFs,
            "_async": true,
            "_group": group
        ]
        if !config.isEmpty {
            body["_config"] = config
        }
        if !excludePatterns.isEmpty {
            body["_filter"] = ["ExcludeRule": excludePatterns]
        }

        let json = try await post(endpoint, body: body)
        return try Self.parseJobId(json)
    }

    func listDirectory(fs: String, remote: String, recurse: Bool = false) async throws -> [RemoteEntry] {
        var body: [String: Any] = ["fs": fs, "remote": remote]
        if recurse {
            body["opt"] = ["recurse": true]
        }
        let json = try await post("operations/list", body: body, timeout: 120)
        guard let list = json["list"] as? [[String: Any]] else {
            throw RcloneRCError.decoding("missing list")
        }
        return list.compactMap { item in
            guard let path = item["Path"] as? String else { return nil }
            func i64(_ key: String) -> Int64 {
                if let n = item[key] as? Int64 { return n }
                if let n = item[key] as? Int { return Int64(n) }
                if let n = item[key] as? Double { return Int64(n) }
                return 0
            }
            return RemoteEntry(
                path: path,
                name: (item["Name"] as? String) ?? (path as NSString).lastPathComponent,
                size: i64("Size"),
                modTime: Self.parseModTime(item["ModTime"] as? String),
                isDir: (item["IsDir"] as? Bool) ?? false,
                mimeType: (item["MimeType"] as? String) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDir != rhs.isDir { return lhs.isDir }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func startCopyFileJob(srcFs: String, srcRemote: String, dstFs: String, dstRemote: String, group: String, config: [String: Any] = [:]) async throws -> Int {
        var body: [String: Any] = [
            "srcFs": srcFs,
            "srcRemote": srcRemote,
            "dstFs": dstFs,
            "dstRemote": dstRemote,
            "_async": true,
            "_group": group
        ]
        if !config.isEmpty {
            body["_config"] = config
        }
        let json = try await post("operations/copyfile", body: body)
        return try Self.parseJobId(json)
    }

    private static func parseModTime(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        return try? Date(raw, strategy: .iso8601.year().month().day().timeZone(separator: .omitted).time(includingFractionalSeconds: true))
    }

    func beginConfiguration(name: String, type: String, parameters: [String: Any]) async throws -> RcloneConfigurationStep {
        let json = try await post("config/create", body: [
            "name": name,
            "type": type,
            "parameters": parameters,
            "opt": ["nonInteractive": true]
        ], timeout: 360)
        return Self.parseConfigurationStep(json)
    }

    func continueConfiguration(
        name: String,
        parameters: [String: Any],
        state: String,
        result: String
    ) async throws -> RcloneConfigurationStep {
        let json = try await post("config/update", body: [
            "name": name,
            "parameters": parameters,
            "opt": [
                "nonInteractive": true,
                "continue": true,
                "state": state,
                "result": result
            ]
        ], timeout: 360)
        return Self.parseConfigurationStep(json)
    }

    func deleteRemoteConfig(name: String) async throws {
        _ = try await post("config/delete", body: ["name": name])
    }

    private static func parseJobId(_ json: [String: Any]) throws -> Int {
        if let jobid = json["jobid"] as? Int {
            return jobid
        }
        if let jobid = json["jobid"] as? Double {
            return Int(jobid)
        }
        throw RcloneRCError.decoding("missing jobid")
    }

    private static func parseProvider(_ json: [String: Any]) -> RcloneProvider? {
        guard let name = json["Name"] as? String, !name.isEmpty else { return nil }
        let options = (json["Options"] as? [[String: Any]] ?? []).compactMap(parseOption)
        return RcloneProvider(
            name: name,
            description: json["Description"] as? String ?? "",
            prefix: json["Prefix"] as? String ?? name,
            options: options
        )
    }

    private static func parseOption(_ json: [String: Any]) -> RcloneProviderOption? {
        guard let name = json["Name"] as? String, !name.isEmpty else { return nil }
        let examples = (json["Examples"] as? [[String: Any]] ?? []).map {
            RcloneOptionExample(value: stringValue($0["Value"]), help: $0["Help"] as? String ?? "")
        }
        return RcloneProviderOption(
            name: name,
            fieldName: json["FieldName"] as? String ?? name,
            help: json["Help"] as? String ?? "",
            type: json["Type"] as? String ?? "string",
            defaultValue: stringValue(json["Default"]),
            required: json["Required"] as? Bool ?? false,
            isPassword: json["IsPassword"] as? Bool ?? false,
            advanced: json["Advanced"] as? Bool ?? false,
            hidden: (json["Hide"] as? Int ?? 0) != 0,
            exclusive: json["Exclusive"] as? Bool ?? false,
            examples: examples
        )
    }

    private static func parseConfigurationStep(_ json: [String: Any]) -> RcloneConfigurationStep {
        RcloneConfigurationStep(
            state: json["State"] as? String ?? json["state"] as? String ?? "",
            option: (json["Option"] as? [String: Any]).flatMap(parseOption),
            error: json["Error"] as? String ?? json["error"] as? String ?? ""
        )
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let value as String: return value
        case let value as Bool: return value ? "true" : "false"
        case let value as Int: return String(value)
        case let value as Int64: return String(value)
        case let value as Double: return String(value)
        default: return ""
        }
    }

    func jobStatus(jobid: Int) async throws -> JobStatusResult {
        let json = try await post("job/status", body: ["jobid": jobid])
        var outputBytes: Int64?
        var outputCount: Int?
        if let output = json["output"] as? [String: Any] {
            if let n = output["bytes"] as? Int64 { outputBytes = n }
            else if let n = output["bytes"] as? Int { outputBytes = Int64(n) }
            else if let n = output["bytes"] as? Double { outputBytes = Int64(n) }
            if let n = output["count"] as? Int { outputCount = n }
            else if let n = output["count"] as? Double { outputCount = Int(n) }
        }
        return JobStatusResult(
            finished: (json["finished"] as? Bool) ?? false,
            success: (json["success"] as? Bool) ?? false,
            error: (json["error"] as? String) ?? "",
            duration: (json["duration"] as? Double) ?? 0,
            outputBytes: outputBytes,
            outputCount: outputCount
        )
    }

    func startSizeJob(fs: String, excludePatterns: [String]) async throws -> Int {
        var body: [String: Any] = ["fs": fs, "remote": "", "_async": true]
        if !excludePatterns.isEmpty {
            body["_filter"] = ["ExcludeRule": excludePatterns]
        }
        let json = try await post("operations/size", body: body)
        return try Self.parseJobId(json)
    }

    func stopJob(jobid: Int) async throws {
        _ = try await post("job/stop", body: ["jobid": jobid])
    }

    func setBandwidthLimit(_ rate: String) async throws {
        _ = try await post("core/bwlimit", body: ["rate": rate])
    }

    func deleteFile(fs: String, remote: String) async throws {
        _ = try await post("operations/deletefile", body: ["fs": fs, "remote": remote], timeout: 120)
    }

    func purgeDirectory(fs: String, remote: String) async throws {
        _ = try await post("operations/purge", body: ["fs": fs, "remote": remote], timeout: 300)
    }

    func stats(group: String) async throws -> TransferStats {
        let json = try await post("core/stats", body: ["group": group])
        return Self.parseStats(json)
    }

    func deleteStats(group: String) async {
        _ = try? await post("core/stats-delete", body: ["group": group])
    }

    // MARK: Parsing

    private static func parseStats(_ json: [String: Any]) -> TransferStats {
        func i64(_ key: String) -> Int64 {
            if let n = json[key] as? Int64 { return n }
            if let n = json[key] as? Int { return Int64(n) }
            if let n = json[key] as? Double { return Int64(n) }
            return 0
        }
        func int(_ key: String) -> Int {
            if let n = json[key] as? Int { return n }
            if let n = json[key] as? Double { return Int(n) }
            return 0
        }
        func dbl(_ key: String) -> Double {
            if let n = json[key] as? Double { return n }
            if let n = json[key] as? Int { return Double(n) }
            return 0
        }
        func optDbl(_ key: String) -> Double? {
            if let n = json[key] as? Double { return n }
            if let n = json[key] as? Int { return Double(n) }
            return nil
        }

        var transferring: [FileProgress] = []
        if let items = json["transferring"] as? [[String: Any]] {
            for item in items {
                guard let name = item["name"] as? String else { continue }
                func fi64(_ key: String) -> Int64 {
                    if let n = item[key] as? Int64 { return n }
                    if let n = item[key] as? Int { return Int64(n) }
                    if let n = item[key] as? Double { return Int64(n) }
                    return 0
                }
                func fint(_ key: String) -> Int {
                    if let n = item[key] as? Int { return n }
                    if let n = item[key] as? Double { return Int(n) }
                    return 0
                }
                func fdbl(_ key: String) -> Double {
                    if let n = item[key] as? Double { return n }
                    if let n = item[key] as? Int { return Double(n) }
                    return 0
                }
                func foptDbl(_ key: String) -> Double? {
                    if let n = item[key] as? Double { return n }
                    if let n = item[key] as? Int { return Double(n) }
                    return nil
                }
                transferring.append(FileProgress(
                    name: name,
                    size: fi64("size"),
                    bytes: fi64("bytes"),
                    percentage: fint("percentage"),
                    speed: fdbl("speed"),
                    speedAvg: fdbl("speedAvg"),
                    eta: foptDbl("eta")
                ))
            }
        }

        var lastError = ""
        if let errs = json["lastError"] as? String {
            lastError = errs
        }

        return TransferStats(
            bytes: i64("bytes"),
            totalBytes: i64("totalBytes"),
            speed: dbl("speed"),
            eta: optDbl("eta"),
            errors: int("errors"),
            checks: int("checks"),
            totalChecks: int("totalChecks"),
            transfers: int("transfers"),
            totalTransfers: int("totalTransfers"),
            elapsedTime: dbl("elapsedTime"),
            fatalError: (json["fatalError"] as? Bool) ?? false,
            retryError: (json["retryError"] as? Bool) ?? false,
            lastError: lastError,
            transferring: transferring
        )
    }
}
