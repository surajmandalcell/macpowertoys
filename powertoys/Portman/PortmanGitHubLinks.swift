import Foundation

nonisolated struct PortmanGitHubLinks: Sendable {
    let pullRequestNumber: Int?
    let pullRequestURL: URL?
    let previewURL: URL?
    let note: String?
}

actor PortmanGitHubLookup {
    static let shared = PortmanGitHubLookup()

    private let session: URLSession
    private var cache: [String: (links: PortmanGitHubLinks, date: Date)] = [:]

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        session = URLSession(configuration: configuration)
    }

    func lookup(root: String, branch: String) async -> PortmanGitHubLinks {
        let key = root + "|" + branch
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < 120 {
            return cached.links
        }
        let result = await fetch(root: root, branch: branch)
        cache[key] = (result, Date())
        return result
    }

    nonisolated static func repository(from remote: String) -> (owner: String, name: String)? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if trimmed.hasPrefix("git@github.com:") {
            path = String(trimmed.dropFirst("git@github.com:".count))
        } else if let url = URLComponents(string: trimmed),
                  url.host == "github.com", (url.user == nil || url.user == "git"),
                  url.password == nil, url.query == nil, url.fragment == nil,
                  ["https", "ssh"].contains(url.scheme ?? "") {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0])
        let rawName = String(parts[1])
        let name = rawName.hasSuffix(".git") ? String(rawName.dropLast(4)) : rawName
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard !owner.isEmpty, !name.isEmpty,
              owner.unicodeScalars.allSatisfy(allowed.contains),
              name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return (owner, name)
    }

    private func fetch(root: String, branch: String) async -> PortmanGitHubLinks {
        guard let remote = try? PortmanScanner.run("/usr/bin/git", ["-C", root, "remote", "get-url", "origin"]),
              let repository = Self.repository(from: remote) else {
            return PortmanGitHubLinks(pullRequestNumber: nil, pullRequestURL: nil,
                                      previewURL: nil, note: "No GitHub origin for this project.")
        }
        let base = "https://api.github.com/repos/\(repository.owner)/\(repository.name)"
        do {
            let pulls = try await request(base + "/pulls", query: [
                URLQueryItem(name: "state", value: "all"),
                URLQueryItem(name: "head", value: "\(repository.owner):\(branch)"),
                URLQueryItem(name: "per_page", value: "1")
            ])
            let firstPull = (pulls as? [[String: Any]])?.first
            let pullURL = (firstPull?["html_url"] as? String).flatMap(URL.init(string:))
            let verifiedPullURL = pullURL?.scheme == "https" && pullURL?.host == "github.com" ? pullURL : nil

            var previewURL: URL?
            if let sha = try? PortmanScanner.run("/usr/bin/git", ["-C", root, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines), sha.count == 40 {
                let deployments = try await request(base + "/deployments", query: [
                    URLQueryItem(name: "sha", value: sha),
                    URLQueryItem(name: "per_page", value: "30")
                ])
                for deployment in (deployments as? [[String: Any]]) ?? [] {
                    guard let environment = deployment["environment"] as? String,
                          environment.localizedCaseInsensitiveContains("preview"),
                          let id = deployment["id"] as? Int else { continue }
                    let statuses = try await request(base + "/deployments/\(id)/statuses", query: [
                        URLQueryItem(name: "per_page", value: "1")
                    ])
                    guard let status = (statuses as? [[String: Any]])?.first,
                          status["state"] as? String == "success",
                          let rawURL = (status["environment_url"] as? String).flatMap({ $0.isEmpty ? nil : $0 })
                            ?? status["target_url"] as? String,
                          let url = URL(string: rawURL), url.scheme == "https" else { continue }
                    previewURL = url
                    break
                }
            }
            return PortmanGitHubLinks(
                pullRequestNumber: verifiedPullURL == nil ? nil : firstPull?["number"] as? Int,
                pullRequestURL: verifiedPullURL, previewURL: previewURL,
                note: verifiedPullURL == nil && previewURL == nil ? "No public PR or preview for this branch." : nil
            )
        } catch {
            return PortmanGitHubLinks(pullRequestNumber: nil, pullRequestURL: nil,
                                      previewURL: nil, note: "Public GitHub links are unavailable.")
        }
    }

    private func request(_ path: String, query: [URLQueryItem]) async throws -> Any {
        var components = URLComponents(string: path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacPowerToys Portman", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}
