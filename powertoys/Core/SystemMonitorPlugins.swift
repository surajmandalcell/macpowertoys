import Foundation

nonisolated struct SystemMonitorPluginManifest: Decodable, Sendable {
    struct Metric: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
    }

    let formatVersion: Int
    let metrics: [Metric]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384 else { throw SystemMonitorPluginError.invalidManifest }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.formatVersion == 1, (1...16).contains(manifest.metrics.count),
              Set(manifest.metrics.map(\.id)).count == manifest.metrics.count,
              manifest.metrics.allSatisfy({ metric in
                  MarketplaceCatalog.isIdentifier(metric.id)
                      && (1...60).contains(metric.title.count)
                      && !metric.title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }) else { throw SystemMonitorPluginError.invalidManifest }
        return manifest
    }
}

nonisolated struct SystemMonitorPluginSample: Decodable, Sendable {
    struct Value: Decodable, Sendable {
        let value: String
        let detail: String?
    }

    let formatVersion: Int
    let values: [String: Value]

    static func decode(_ output: String, manifest: SystemMonitorPluginManifest) throws -> Self {
        guard output.utf8.count <= 16_384 else { throw SystemMonitorPluginError.invalidSample }
        let sample = try JSONDecoder().decode(Self.self, from: Data(output.utf8))
        let ids = Set(manifest.metrics.map(\.id))
        guard sample.formatVersion == 1, !sample.values.isEmpty,
              sample.values.allSatisfy({ id, item in
                  ids.contains(id)
                      && (1...80).contains(item.value.count)
                      && !item.value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                      && (item.detail.map { detail in
                          detail.count <= 100
                              && !detail.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                      } ?? true)
              }) else { throw SystemMonitorPluginError.invalidSample }
        return sample
    }
}

nonisolated enum SystemMonitorPluginError: LocalizedError {
    case invalidManifest
    case invalidSample
    case failed

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "The monitor plugin manifest is invalid."
        case .invalidSample: "The monitor plugin returned invalid data."
        case .failed: "The monitor plugin could not collect data."
        }
    }
}

nonisolated struct SystemMonitorPlugin: Identifiable, Sendable {
    let id: String
    let name: String
    let executableURL: URL
    let manifest: SystemMonitorPluginManifest

    static func load(receipt: MarketplaceReceipt, appURL: URL) -> Self? {
        guard MarketplaceCatalog.isIdentifier(receipt.toolID),
              let bundle = Bundle(url: appURL), bundle.bundleIdentifier == receipt.bundleID,
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else { return nil }
        let manifestURL = appURL.appendingPathComponent("Contents/Resources/monitor.json")
        guard let size = try? manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16_384,
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? SystemMonitorPluginManifest.decode(data) else { return nil }
        return Self(id: receipt.toolID, name: receipt.name, executableURL: executableURL, manifest: manifest)
    }

    func sample() async throws -> SystemMonitorPluginSample {
        let result = try await SSHProcessRunner.run(
            executableURL: executableURL,
            arguments: ["--macpowertoys-monitor-sample"],
            environment: SSHKeyAccessConfiguration.baseEnvironment(),
            maximumOutputBytes: 16_384,
            timeout: 5
        )
        guard result.status == 0 else { throw SystemMonitorPluginError.failed }
        return try SystemMonitorPluginSample.decode(result.standardOutput, manifest: manifest)
    }
}
