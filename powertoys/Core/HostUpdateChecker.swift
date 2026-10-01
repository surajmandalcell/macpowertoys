import Foundation
import Observation

nonisolated struct HostAppMetadata {
    static let current = HostAppMetadata(bundle: .main)
    static let repository = URL(string: "https://github.com/surajmandalcell/macpowertoys")!
    static let releases = repository.appendingPathComponent("releases")
    static let developer = "Suraj Mandal"
    static let contact = "surajmandalcell@gmail.com"

    let version: String
    let build: String
    let sourceCommit: String

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable"
        sourceCommit = bundle.object(forInfoDictionaryKey: "MPTSourceCommit") as? String ?? "Unavailable"
    }
}

@Observable
@MainActor
final class HostUpdateChecker {
    nonisolated enum State: Equatable, Sendable {
        case idle, checking, current
        case available(version: String, url: URL)
        case failed(String)
    }

    static let shared = HostUpdateChecker()
    private(set) var state = State.idle
    var isChecking: Bool { state == .checking }
    private let installedVersion: String
    private let fetch: @Sendable () async throws -> Data
    private var task: Task<Void, Never>?

    init(installedVersion: String = HostAppMetadata.current.version,
         fetch: @escaping @Sendable () async throws -> Data = { try await HostUpdateChecker.fetchRelease() }) {
        self.installedVersion = installedVersion
        self.fetch = fetch
    }

    func check() {
        guard !isChecking else { return }
        state = .checking
        task = Task {
            do {
                let data = try await fetch()
                let version = installedVersion
                state = try await Task.detached(priority: .utility) {
                    try Self.result(for: data, installedVersion: version)
                }.value
            }
            catch { state = .failed("Could not check for updates. \(error.localizedDescription) Try again.") }
            task = nil
        }
    }

    nonisolated static func fetchRelease() async throws -> Data {
        let url = URL(string: "https://api.github.com/repos/surajmandalcell/macpowertoys/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    nonisolated static func result(for data: Data, installedVersion: String) throws -> State {
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard !release.draft, !release.prerelease,
              let latest = AppVersion(version), let installed = AppVersion(installedVersion),
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.user == nil, release.html_url.password == nil,
              release.html_url.path.hasPrefix(HostAppMetadata.releases.path + "/tag/") else {
            throw URLError(.cannotParseResponse)
        }
        return latest > installed ? .available(version: version, url: release.html_url) : .current
    }

    private nonisolated struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }
}
