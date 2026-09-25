import Foundation
import Observation

nonisolated enum FanPreset: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case cool = "Cool"
    case max = "Max"

    var id: String { rawValue }
}

nonisolated struct FanReading: Decodable, Sendable {
    let index: Int
    let actualRPM: Double?
    let maximumRPM: Double?
    let mode: String?
}

nonisolated struct FanSnapshot: Sendable {
    let fans: [FanReading]
    let profile: String?
    let canControl: Bool

    var averageRPM: Int? {
        let values = fans.compactMap(\.actualRPM).filter { $0.isFinite && $0 >= 0 }
        guard values.count == fans.count, !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return average < 100_000 ? Int(average.rounded()) : nil
    }

    var utilization: Int? {
        let fractions = fans.compactMap { fan -> Double? in
            guard let actual = fan.actualRPM, let maximum = fan.maximumRPM,
                  actual.isFinite, actual >= 0, maximum.isFinite, maximum > 0 else { return nil }
            return min(max(actual / maximum, 0), 1)
        }
        guard fractions.count == fans.count, !fractions.isEmpty else { return nil }
        return Int((fractions.reduce(0, +) / Double(fractions.count) * 100).rounded())
    }

    var detectedPreset: FanPreset? {
        guard !fans.isEmpty else { return nil }
        return switch profile {
        case "auto" where fans.allSatisfy({ ["auto", "system"].contains($0.mode?.lowercased() ?? "") }): .auto
        case "full": .max
        default: nil
        }
    }

    var hasExternalManualControl: Bool {
        profile == nil && fans.contains { ["manual", "forced"].contains($0.mode?.lowercased() ?? "") }
    }
}

nonisolated enum FanCommand {
    private struct JSONStatus: Decodable {
        let profile: String?
        let fans: [FanReading]
    }

    private static let smctlPaths = ["/opt/homebrew/bin/smctl", "/usr/local/bin/smctl"]
    private static let statsPath = "/Applications/Stats.app/Contents/Resources/smc"
    private static let controlQueue = DispatchQueue(label: "com.surajmandal.macpowertoys.fan-control")

    static var smctlPath: String? {
        smctlPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func read() -> FanSnapshot? {
        if let smctlPath {
            if let output = try? run(smctlPath, ["fan", "status", "--json"]),
               let status = try? JSONDecoder().decode(JSONStatus.self, from: Data(output.utf8)) {
                return FanSnapshot(fans: status.fans, profile: status.profile,
                                   canControl: !status.fans.isEmpty)
            }
            if let output = try? run(smctlPath, ["sensors", "--json"]),
               let status = try? JSONDecoder().decode(JSONStatus.self, from: Data(output.utf8)) {
                return FanSnapshot(fans: status.fans, profile: nil, canControl: false)
            }
        }
        if FileManager.default.isExecutableFile(atPath: statsPath),
           let output = try? run(statsPath, ["fans"]) {
            return parseStatsFans(output)
        }
        return nil
    }

    static func parseStatsFans(_ output: String) -> FanSnapshot? {
        guard output.contains("Number of fans:") else { return nil }
        var fans: [FanReading] = []
        for block in output.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n").map(String.init)
            guard let heading = lines.first,
                  let index = Int(heading.split(separator: ":").first ?? ""),
                  heading.contains("Fan") else { continue }
            var fields: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let separator = line.firstIndex(of: ":") else { continue }
                fields[String(line[..<separator])] = String(line[line.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
            }
            fans.append(FanReading(
                index: index,
                actualRPM: fields["Actual speed"].flatMap(Double.init),
                maximumRPM: fields["Maximum speed"].flatMap(Double.init),
                mode: fields["Mode"]
            ))
        }
        return FanSnapshot(fans: fans, profile: nil, canControl: false)
    }

    static func arguments(for preset: FanPreset) -> [String] {
        ["fan", "profile", preset == .auto ? "auto" : "full"]
    }

    static func apply(_ preset: FanPreset, completion: @escaping @Sendable (String?) -> Void) {
        controlQueue.async {
            do {
                try applyOnQueue(preset)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    static func restoreAutomatic() {
        controlQueue.sync { try? applyOnQueue(.auto) }
    }

    private static func applyOnQueue(_ preset: FanPreset) throws {
        guard let smctlPath else { throw FanError("Install smctl to enable fan control.") }
        _ = try run(smctlPath, arguments(for: preset))
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        timeout.cancel()
        let output = String(decoding: data.prefix(262_144), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw FanError(output.isEmpty ? "The fan helper did not respond." : output)
        }
        return output
    }
}

nonisolated private struct FanError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@Observable
@MainActor
final class FanControlService {
    static let shared = FanControlService()
    static weak var current: FanControlService?

    private(set) var snapshot: FanSnapshot?
    private(set) var selectedPreset: FanPreset?
    private(set) var errorMessage: String?
    private(set) var isChanging = false
    private var owners = Set<String>()
    private var pollTask: Task<Void, Never>?
    private var coolResetTask: Task<Void, Never>?
    private var ownsManualControl = false
    private var hasPendingManualCommand = false
    private var revision = 0

    private init() { Self.current = self }

    var pollOwnerCount: Int { pollTask == nil ? 0 : 1 }
    var isAvailable: Bool { snapshot?.fans.isEmpty == false }
    var canControl: Bool { snapshot?.canControl == true }
    var canRestoreAutomatic: Bool { ownsManualControl && FanCommand.smctlPath != nil }

    func start(owner: String) {
        guard owners.insert(owner).inserted, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop(owner: String) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        revision &+= 1
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        let currentRevision = revision
        let result = await Task.detached(priority: .utility) { FanCommand.read() }.value
        guard currentRevision == revision, !owners.isEmpty else { return }
        snapshot = result
        if !ownsManualControl { selectedPreset = result?.detectedPreset }
    }

    func select(_ preset: FanPreset) {
        guard !isChanging,
              snapshot?.canControl == true || (preset == .auto && ownsManualControl) else { return }
        isChanging = true
        hasPendingManualCommand = preset != .auto
        errorMessage = nil
        FanCommand.apply(preset) { [weak self] commandError in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasPendingManualCommand = false
                if let commandError {
                    self.errorMessage = commandError
                } else {
                    self.coolResetTask?.cancel()
                    self.coolResetTask = nil
                    self.ownsManualControl = preset != .auto
                    self.selectedPreset = preset
                    if preset == .cool {
                        self.coolResetTask = Task { [weak self] in
                            try? await Task.sleep(for: .seconds(600))
                            guard !Task.isCancelled else { return }
                            self?.select(.auto)
                        }
                    }
                }
                await self.refresh()
                self.isChanging = false
            }
        }
    }

    func restoreAutomaticOnExit() {
        guard ownsManualControl || hasPendingManualCommand else { return }
        coolResetTask?.cancel()
        FanCommand.restoreAutomatic()
        ownsManualControl = false
        hasPendingManualCommand = false
    }
}
