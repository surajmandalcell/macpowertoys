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

    private static let statsPath = "/Applications/Stats.app/Contents/Resources/smc"
    private static let controlQueue = DispatchQueue(label: "com.surajmandal.macpowertoys.fan-control")

    static func read() -> FanSnapshot? {
        if let snapshot = NativeFanReader.snapshot() { return snapshot }
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

    static func apply(_ preset: FanPreset, completion: @escaping @Sendable (String?) -> Void) {
        controlQueue.async {
            do {
                try applyBuiltIn(preset)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    private static func applyBuiltIn(_ preset: FanPreset) throws {
        let reply = HelperReply()
        let (connection, proxy) = helperConnection(reply: reply)
        proxy?.applyFanPreset(preset.rawValue) { reply.finish($0) }
        if proxy == nil { reply.finish("The built-in fan helper is unavailable.") }
        let message = reply.wait()
        // The helper restores Auto when the connection that set Cool or Max closes, so hold it while manual.
        let previous = manualConnection
        if message.isEmpty && preset != .auto {
            manualConnection = connection
        } else {
            manualConnection = nil
            connection.invalidate()
        }
        if previous !== manualConnection { previous?.invalidate() }
        if !message.isEmpty { throw FanError(message) }
    }

    // Touched only on controlQueue.
    nonisolated(unsafe) private static var manualConnection: NSXPCConnection?

    /// The running helper's CFBundleVersion, or nil when it does not answer. Blocks; call off main.
    static func helperVersion() -> Int? {
        let reply = HelperReply()
        let (connection, proxy) = helperConnection(reply: reply)
        proxy?.neighborSnapshot { _, version in reply.finish(version) }
        if proxy == nil { reply.finish("") }
        let version = reply.wait(seconds: 5)
        connection.invalidate()
        return Int(version)
    }

    /// Asks the root helper to restart Core Audio. Returns an empty string on success. Blocks; call off main.
    static func restartAudio() -> String {
        let reply = HelperReply()
        let (connection, proxy) = helperConnection(reply: reply)
        proxy?.restartAudio { reply.finish($0) }
        if proxy == nil { reply.finish("The built-in helper is unavailable.") }
        let message = reply.wait(seconds: 10)
        connection.invalidate()
        return message
    }

    private static func helperConnection(reply: HelperReply) -> (NSXPCConnection, MacPowerToysHelperXPCProtocol?) {
        let connection = NSXPCConnection(
            machServiceName: MacPowerToysHelperContract.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: MacPowerToysHelperXPCProtocol.self)
        connection.setCodeSigningRequirement(MacPowerToysHelperContract.helperRequirement)
        connection.interruptionHandler = { reply.finish("The built-in fan helper stopped.") }
        connection.invalidationHandler = { reply.finish("The built-in fan helper is unavailable.") }
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler {
            reply.finish($0.localizedDescription)
        } as? MacPowerToysHelperXPCProtocol
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
            let chunk = autoreleasepool { pipe.fileHandleForReading.readData(ofLength: 8_192) }
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

nonisolated struct FanControlPresentation: Equatable, Sendable {
    var status = "— RPM · —%"
    var rpm = "— RPM"
    /// A completed read found no fans, so the panel hides the Fan row.
    var hasNoFans = false
    var detail = "Fan data unavailable"
    var activePreset: FanPreset?
    var selectedPreset: FanPreset?
    var canControl = false
    var canRestoreAutomatic = false
    var canInstallHelper = false
    var isUnsupportedBuild = false
    var isChanging = false
    var hasCompletedRead = false
    var hasError = false

    init(snapshot: FanSnapshot? = nil, selectedPreset: FanPreset? = nil, errorMessage: String? = nil,
         canRestoreAutomatic: Bool = false, canInstallHelper: Bool = false, isUnsupportedBuild: Bool = false,
         isChanging: Bool = false, hasCompletedRead: Bool = false) {
        rpm = snapshot?.averageRPM.map { $0.formatted() + " RPM" } ?? "— RPM"
        let utilization = snapshot?.utilization.map { "\($0)%" } ?? "—%"
        status = "\(rpm) · \(utilization)"
        hasNoFans = snapshot?.fans.isEmpty == true
        self.selectedPreset = selectedPreset
        activePreset = Self.reportedPreset(snapshot, selectedPreset: selectedPreset)
        canControl = snapshot?.canControl == true
        self.canRestoreAutomatic = canRestoreAutomatic
        self.canInstallHelper = canInstallHelper
        self.isUnsupportedBuild = isUnsupportedBuild
        self.isChanging = isChanging
        self.hasCompletedRead = hasCompletedRead
        hasError = errorMessage != nil
        detail = Self.detail(snapshot: snapshot, selectedPreset: selectedPreset, errorMessage: errorMessage,
                             canControl: canControl, canRestoreAutomatic: canRestoreAutomatic,
                             isUnsupportedBuild: isUnsupportedBuild, activePreset: activePreset)
    }

    static func canSelect(_ preset: FanPreset, canControl: Bool, canRestoreAutomatic: Bool, isChanging: Bool) -> Bool {
        !isChanging && (canControl || (preset == .auto && canRestoreAutomatic))
    }

    func canSelect(_ preset: FanPreset?) -> Bool {
        guard let preset else { return false }
        return Self.canSelect(preset, canControl: canControl, canRestoreAutomatic: canRestoreAutomatic, isChanging: isChanging)
    }

    static func reportedPreset(_ snapshot: FanSnapshot?, selectedPreset: FanPreset?) -> FanPreset? {
        if let selectedPreset { return selectedPreset }
        guard let snapshot, !snapshot.fans.isEmpty else { return nil }
        if let detected = snapshot.detectedPreset { return detected }
        return snapshot.fans.allSatisfy { ["auto", "system"].contains($0.mode?.lowercased() ?? "") } ? .auto : nil
    }

    private static func detail(snapshot: FanSnapshot?, selectedPreset: FanPreset?, errorMessage: String?,
                               canControl: Bool, canRestoreAutomatic: Bool, isUnsupportedBuild: Bool,
                               activePreset: FanPreset?) -> String {
        if let error = errorMessage { return error }
        guard let snapshot = snapshot else { return "Fan data unavailable" }
        guard !snapshot.fans.isEmpty else { return "No fans detected" }
        if selectedPreset == nil, snapshot.hasExternalManualControl {
            return canRestoreAutomatic
                ? "Manual fan speed set elsewhere · Auto restores macOS"
                : "Manual fan speed set elsewhere · read only"
        }
        if activePreset == .auto { return "Auto follows macOS" }
        guard canControl else {
            if canRestoreAutomatic {
                return snapshot.hasExternalManualControl
                    ? "Manual control active · Auto restores macOS"
                    : "Fan helper unavailable · try Auto"
            }
            if isUnsupportedBuild { return FanHelperService.unsupportedMessage }
            if snapshot.fans.contains(where: { $0.mode?.hasPrefix("unknown") == true }) {
                return "Fan control unavailable on this Mac"
            }
            return snapshot.hasExternalManualControl
                ? "Manual fan speed set elsewhere · read only"
                : "Read only · install the fan helper"
        }
        switch selectedPreset {
        case .auto: return "Controlled by macOS"
        case .cool: return "Cooling boost · Auto in 10 minutes"
        case .max: return "Maximum cooling"
        case nil: return "Manual control active"
        }
    }

}

@Observable
@MainActor
final class FanControlService {
    static let shared = FanControlService()
    static weak var current: FanControlService?
    nonisolated static let minimumDisplayInterval: Duration = .milliseconds(250)

    private(set) var snapshot: FanSnapshot? { didSet { scheduleDisplay() } }
    private(set) var hasCompletedRead = false { didSet { scheduleDisplay() } }
    private(set) var selectedPreset: FanPreset? { didSet { scheduleDisplay() } }
    private(set) var errorMessage: String? { didSet { scheduleDisplay() } }
    private(set) var isChanging = false { didSet { scheduleDisplay() } }
    private(set) var display = FanControlPresentation()
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var lastDisplayPublication: ContinuousClock.Instant?
    @ObservationIgnored private var displayRevision = 0
    @ObservationIgnored private let readSnapshot: @Sendable () -> FanSnapshot?
    @ObservationIgnored private let applyPreset: @Sendable (FanPreset, @escaping @Sendable (String?) -> Void) -> Void
    private var owners = Set<String>()
    private var pollTask: Task<Void, Never>?
    private var coolResetTask: Task<Void, Never>?
    private var ownsManualControl = false
    private var hasPendingManualCommand = false
    private var isRestoringOnExit = false
    private var commandRevision = 0
    private var revision = 0

    private convenience init() {
        self.init(readSnapshot: FanCommand.read)
        Self.current = self
    }

    init(readSnapshot: @escaping @Sendable () -> FanSnapshot?,
         applyPreset: @escaping @Sendable (FanPreset, @escaping @Sendable (String?) -> Void) -> Void = FanCommand.apply) {
        self.readSnapshot = readSnapshot
        self.applyPreset = applyPreset
    }

    var pollOwnerCount: Int { pollTask == nil ? 0 : 1 }
    var isAvailable: Bool { snapshot?.fans.isEmpty == false }
    var canControl: Bool { snapshot?.canControl == true }
    var canRestoreAutomatic: Bool {
        (ownsManualControl || hasPendingManualCommand || snapshot?.hasExternalManualControl == true)
            && FanHelperService.shared.isEnabled
    }
    var canInstallHelper: Bool { FanHelperService.shared.canInstall }
    var isUnsupportedBuild: Bool { FanHelperService.shared.status == .unsupported }

    /// Installs the helper (one macOS admin password prompt) without changing the fans.
    func enableControl() async {
        guard !isChanging else { return }
        isChanging = true
        errorMessage = await FanHelperService.shared.install()
        await refresh()
        isChanging = false
    }

    func start(owner: String) {
        guard owners.insert(owner).inserted, pollTask == nil else { return }
        scheduleDisplay()
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
        displayTask?.cancel()
        displayTask = nil
    }

    func refresh() async {
        let currentRevision = revision
        let readSnapshot = readSnapshot
        let result = await Task.detached(priority: .utility) { readSnapshot() }.value
        guard currentRevision == revision, !owners.isEmpty, !isRestoringOnExit else { return }
        hasCompletedRead = true
        if let result {
            // A helper that is missing or older still allows a choice: the first write installs it.
            let helper = FanHelperService.shared
            let nativeControl = (helper.isEnabled || helper.canInstall)
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
        guard !isRestoringOnExit else { return }
        guard FanControlPresentation.canSelect(preset, canControl: canControl,
                                              canRestoreAutomatic: canRestoreAutomatic, isChanging: isChanging) else { return }
        let helper = FanHelperService.shared
        guard helper.canInstall else { send(preset); return }
        // Auto while macOS already runs the fans needs no helper, so it never asks for a password.
        guard preset != .auto || snapshot?.hasExternalManualControl == true else { return }
        isChanging = true
        Task {
            let message = await helper.install()
            isChanging = false
            if let message { errorMessage = message } else { send(preset) }
        }
    }

    private func send(_ preset: FanPreset, done: CheckedContinuation<Bool, Never>? = nil) {
        isChanging = true
        hasPendingManualCommand = preset != .auto
        errorMessage = nil
        commandRevision &+= 1
        let currentCommand = commandRevision
        applyPreset(preset) { [weak self] commandError in
            Task { @MainActor [weak self] in
                guard let self, currentCommand == self.commandRevision else { done?.resume(returning: false); return }
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
                            await self?.revertCoolToAutomatic()
                        }
                    }
                }
                done?.resume(returning: commandError == nil)
                await self.refresh()
                guard currentCommand == self.commandRevision else { return }
                self.isChanging = false
            }
        }
    }

    // Skips the UI gate and retries, so a failed revert shows an error instead of a stale Cool countdown.
    private func revertCoolToAutomatic() async {
        for delay in [0, 30, 120] {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, !isRestoringOnExit, selectedPreset == .cool else { return }
            if isChanging { continue }
            if await withCheckedContinuation({ send(.auto, done: $0) }) { return }
        }
        guard !Task.isCancelled, selectedPreset == .cool else { return }
        errorMessage = "Cool could not return to Auto. Select Auto to retry."
    }

    func restoreAutomaticOnExit() async throws {
        guard !isRestoringOnExit else { throw FanError("Automatic fan restoration is already in progress.") }
        guard ownsManualControl || hasPendingManualCommand else { return }
        isRestoringOnExit = true
        revision &+= 1
        isChanging = true
        commandRevision &+= 1
        coolResetTask?.cancel()
        coolResetTask = nil
        defer {
            revision &+= 1
            isRestoringOnExit = false
            isChanging = false
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                applyPreset(.auto) { message in
                    if let message { continuation.resume(throwing: FanError(message)) }
                    else { continuation.resume() }
                }
            }
            ownsManualControl = false
            hasPendingManualCommand = false
            selectedPreset = .auto
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func scheduleDisplay() {
        displayRevision &+= 1
        guard !owners.isEmpty, displayTask == nil else { return }
        displayTask = Task { [weak self] in
            guard let self else { return }
            if let lastDisplayPublication {
                try? await Task.sleep(until: lastDisplayPublication.advanced(by: Self.minimumDisplayInterval), clock: .continuous)
            }
            guard !Task.isCancelled, !owners.isEmpty else { return }
            let currentRevision = displayRevision
            let snapshot = snapshot
            let selectedPreset = selectedPreset
            let errorMessage = errorMessage
            let canRestoreAutomatic = canRestoreAutomatic
            let canInstallHelper = canInstallHelper
            let isUnsupportedBuild = isUnsupportedBuild
            let isChanging = isChanging
            let hasCompletedRead = hasCompletedRead
            let next = await Task.detached(priority: .utility) {
                FanControlPresentation(snapshot: snapshot, selectedPreset: selectedPreset, errorMessage: errorMessage,
                                       canRestoreAutomatic: canRestoreAutomatic, canInstallHelper: canInstallHelper,
                                       isUnsupportedBuild: isUnsupportedBuild, isChanging: isChanging,
                                       hasCompletedRead: hasCompletedRead)
            }.value
            guard !Task.isCancelled, !owners.isEmpty else { return }
            displayTask = nil
            if currentRevision == displayRevision {
                if display != next {
                    display = next
                    lastDisplayPublication = .now
                }
            } else {
                scheduleDisplay()
            }
        }
    }
}
