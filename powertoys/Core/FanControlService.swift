import Darwin
import Foundation
import Observation
import ServiceManagement

nonisolated enum FanCommand {
    private final class HelperReply: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var result: String?

        func finish(_ value: String) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = value
            lock.unlock()
            semaphore.signal()
        }

        func wait(seconds: Double = 8) -> String {
            guard semaphore.wait(timeout: .now() + seconds) == .success else {
                return "The built-in fan helper did not respond."
            }
            lock.lock()
            defer { lock.unlock() }
            return result ?? "The built-in fan helper did not respond."
        }
    }

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
               let snapshot = parseSmctlStatus(output) {
                return snapshot
            }
            if let output = try? run(smctlPath, ["sensors", "--json"]),
               let status = try? JSONDecoder().decode(JSONStatus.self, from: Data(output.utf8)) {
                return FanSnapshot(fans: status.fans, profile: nil, canControl: false)
            }
        }
        if let snapshot = NativeFanReader.snapshot() { return snapshot }
        if FileManager.default.isExecutableFile(atPath: statsPath),
           let output = try? run(statsPath, ["fans"]) {
            return parseStatsFans(output)
        }
        return nil
    }

    static func parseSmctlStatus(_ output: String) -> FanSnapshot? {
        guard let status = try? JSONDecoder().decode(JSONStatus.self, from: Data(output.utf8)) else {
            return nil
        }
        let knownModes = ["auto", "manual", "system"]
        return FanSnapshot(
            fans: status.fans,
            profile: status.profile,
            canControl: !status.fans.isEmpty && status.fans.allSatisfy {
                knownModes.contains($0.mode?.lowercased() ?? "")
            }
        )
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
        if let smctlPath {
            _ = try run(smctlPath, arguments(for: preset))
        } else {
            try applyBuiltIn(preset)
        }
    }

    private static func applyBuiltIn(_ preset: FanPreset) throws {
        let reply = HelperReply()
        let (connection, proxy) = helperConnection(reply: reply)
        proxy?.applyFanPreset(preset.rawValue) { reply.finish($0) }
        if proxy == nil { reply.finish("The built-in fan helper is unavailable.") }
        let message = reply.wait()
        connection.invalidate()
        if !message.isEmpty { throw FanError(message) }
    }

    static func helperSourceCommit() -> String? {
        let reply = HelperReply()
        let (connection, proxy) = helperConnection(reply: reply)
        proxy?.neighborSnapshot { _, commit in reply.finish(commit) }
        if proxy == nil { reply.finish("") }
        let commit = reply.wait(seconds: 2)
        connection.invalidate()
        return commit.count == 40 && commit.allSatisfy(\.isHexDigit) ? commit : nil
    }

    private static func helperConnection(reply: HelperReply) -> (NSXPCConnection, NetToysNeighborXPCProtocol?) {
        let connection = NSXPCConnection(
            machServiceName: NetToysNeighborServiceContract.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: NetToysNeighborXPCProtocol.self)
        connection.setCodeSigningRequirement(NetToysNeighborServiceContract.helperRequirement)
        connection.interruptionHandler = { reply.finish("The built-in fan helper stopped.") }
        connection.invalidationHandler = { reply.finish("The built-in fan helper is unavailable.") }
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler {
            reply.finish($0.localizedDescription)
        } as? NetToysNeighborXPCProtocol
        return (connection, proxy)
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let timeout = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        var data = Data()
        var exceeded = false
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 8_192)
            if chunk.isEmpty { break }
            let remaining = max(262_144 - data.count, 0)
            data.append(contentsOf: chunk.prefix(remaining))
            exceeded = exceeded || chunk.count > remaining
        }
        process.waitUntilExit()
        timeout.cancel()
        guard !exceeded else { throw FanError("The fan helper returned too much data.") }
        let output = String(decoding: data, as: UTF8.self)
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
    private(set) var hasCompletedRead = false
    private(set) var selectedPreset: FanPreset?
    private(set) var errorMessage: String?
    private(set) var isChanging = false
    private var owners = Set<String>()
    private var pollTask: Task<Void, Never>?
    private var coolResetTask: Task<Void, Never>?
    private var ownsManualControl = false
    private var hasPendingManualCommand = false
    private var helperCommit: String?
    private var revision = 0

    private init() { Self.current = self }

    var pollOwnerCount: Int { pollTask == nil ? 0 : 1 }
    var isAvailable: Bool { snapshot?.fans.isEmpty == false }
    var canControl: Bool { snapshot?.canControl == true }
    var canRestoreAutomatic: Bool {
        (ownsManualControl || snapshot?.hasExternalManualControl == true)
            && (FanCommand.smctlPath != nil || NetToysNeighborServiceManager.shared.isEnabled)
    }
    var needsApproval: Bool { NetToysNeighborServiceManager.shared.status == .requiresApproval }
    var needsHelperUpdate: Bool {
        guard let helperCommit else { return false }
        return helperCommit != Bundle.main.object(forInfoDictionaryKey: "MPTSourceCommit") as? String
    }

    func enableControl() async {
        let manager = NetToysNeighborServiceManager.shared
        if needsHelperUpdate {
            do { try await manager.restart() }
            catch { errorMessage = error.localizedDescription; return }
            helperCommit = nil
        }
        guard manager.enable(openSettings: false) else {
            errorMessage = needsApproval
                ? "Allow MacPowerToys under Background App Activity in Login Items."
                : "macOS could not enable the built-in fan helper."
            return
        }
        errorMessage = nil
        await refresh()
    }

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
        if NetToysNeighborServiceManager.shared.isEnabled, helperCommit == nil {
            helperCommit = await Task.detached(priority: .utility) { FanCommand.helperSourceCommit() }.value
        }
        guard currentRevision == revision, !owners.isEmpty else { return }
        hasCompletedRead = true
        if let result {
            let nativeControl = NetToysNeighborServiceManager.shared.isEnabled
                && !needsHelperUpdate && helperCommit != nil
                && !result.fans.isEmpty
                && (!result.hasExternalManualControl || ownsManualControl)
                && result.fans.allSatisfy { ["auto", "manual", "system"].contains($0.mode ?? "") }
            snapshot = FanSnapshot(fans: result.fans, profile: result.profile,
                                   canControl: result.canControl || nativeControl)
        } else {
            snapshot = nil
        }
        if !ownsManualControl { selectedPreset = snapshot?.detectedPreset }
    }

    func select(_ preset: FanPreset) {
        guard !isChanging,
              snapshot?.canControl == true || (preset == .auto && canRestoreAutomatic) else { return }
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
