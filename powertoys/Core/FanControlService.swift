import AppKit
import Darwin
import Foundation
import Observation
import ServiceManagement

nonisolated enum FanCommand {
    final class HelperReply: @unchecked Sendable {
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
    static let controlQueue = DispatchQueue(label: "com.surajmandal.macpowertoys.fan-control")

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
                try FanDriver.apply(preset)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// Called on the control queue when Cool or Max ends without a request (macOS took control, the helper stopped).
    static func setManualLostHandler(_ handler: @escaping @Sendable (String) -> Void) {
        controlQueue.async { FanDriver.onManualLost = handler }
    }

    /// The running helper's CFBundleVersion, or nil when it does not answer. Blocks; call off main.
    static func helperVersion() -> Int? {
        let connection = helperConnection()
        defer { connection.invalidate() }
        let version = request(on: connection, seconds: 5) { helper, reply in
            helper.neighborSnapshot { _, version in reply(version) }
        }
        return Int(version)
    }

    /// Asks the root helper to restart Core Audio. Returns an empty string on success. Blocks; call off main.
    static func restartAudio() -> String {
        let connection = helperConnection()
        defer { connection.invalidate() }
        return request(on: connection, seconds: 10) { helper, reply in helper.restartAudio(reply: reply) }
    }

    static func helperConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: MacPowerToysHelperContract.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: MacPowerToysHelperXPCProtocol.self)
        connection.setCodeSigningRequirement(MacPowerToysHelperContract.helperRequirement)
        connection.resume()
        return connection
    }

    /// One blocking helper call. The error handler covers a helper that stops or refuses the connection.
    static func request(on connection: NSXPCConnection, seconds: Double = 8,
                        _ send: (MacPowerToysHelperXPCProtocol, @escaping @Sendable (String) -> Void) -> Void) -> String {
        let reply = HelperReply()
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ reply.finish($0.localizedDescription) })
                as? MacPowerToysHelperXPCProtocol else { return "The built-in fan helper is unavailable." }
        send(helper) { reply.finish($0) }
        return reply.wait(seconds: seconds)
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

nonisolated struct FanError: LocalizedError {
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
    var cpuCelsius: Int?
    var inputName = FanInput.cpuName

    init(snapshot: FanSnapshot? = nil, selectedPreset: FanPreset? = nil, errorMessage: String? = nil,
         canRestoreAutomatic: Bool = false, canInstallHelper: Bool = false, isUnsupportedBuild: Bool = false,
         isChanging: Bool = false, hasCompletedRead: Bool = false, cpuCelsius: Double? = nil, inputName: String = FanInput.cpuName) {
        self.cpuCelsius = cpuCelsius.map { Int($0.rounded()) }
        self.inputName = inputName
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
        case .cool: return "Cool · fans follow the chip temperature"
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
    /// The Fan input, the higher of the CPU and GPU die averages over 20 s (`FanInput`), and its name.
    private(set) var cpuCelsius: Double? { didSet { scheduleDisplay() } }
    private(set) var inputName = FanInput.cpuName
    @ObservationIgnored private var input = FanInput()
    @ObservationIgnored private var lastTemperatureRead: ContinuousClock.Instant?
    private(set) var display = FanControlPresentation()
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var lastDisplayPublication: ContinuousClock.Instant?
    @ObservationIgnored private var displayRevision = 0
    @ObservationIgnored private let readSnapshot: @Sendable () -> FanSnapshot?
    @ObservationIgnored private let readTemperature: @Sendable () -> FanTemperatures?
    @ObservationIgnored private let applyPreset: @Sendable (FanPreset, @escaping @Sendable (String?) -> Void) -> Void
    private var owners = Set<String>()
    private var pollTask: Task<Void, Never>?
    private var ownsManualControl = false
    private var lastRequested: FanPreset?
    private var hasPendingManualCommand = false
    private var isRestoringOnExit = false
    private var commandRevision = 0
    private var revision = 0

    nonisolated static let savedPresetKey = "fan.savedPreset"
    /// The mode the owner last chose. Launch and wake apply it again; the helper's safety reset may have set Auto.
    static var savedPreset: FanPreset {
        FanPreset(rawValue: UserDefaults.standard.string(forKey: savedPresetKey) ?? "") ?? .auto
    }
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private convenience init() {
        self.init(readSnapshot: FanCommand.read, readTemperature: CPUTemperatureSensor.read)
        Self.current = self
        if let moved = FanCurve.migrateToAverageScale() { LogManager.shared.info(moved, source: "Fan") }
        FanCommand.setManualLostHandler { reason in
            Task { @MainActor in FanControlService.shared.manualControlLost(reason) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    await FanControlService.shared.restoreSavedPreset(afterWake: true)
                }
            }
    }

    /// Applies the saved Cool or Max with no prompt. A missing or outdated helper leaves Auto and shows the bell item.
    func restoreSavedPreset(afterWake: Bool = false) async {
        let saved = Self.savedPreset
        guard saved != .auto, !isRestoringOnExit, !isChanging else { return }
        let owner = "saved-preset"
        start(owner: owner)
        defer { stop(owner: owner) }
        if !afterWake {
            selectedPreset = saved
            hasPendingManualCommand = true
        }
        await FanHelperService.shared.refresh()
        guard FanHelperService.shared.isEnabled else {
            hasPendingManualCommand = false
            await refresh()
            LogManager.shared.warning("Fan: saved \(saved.rawValue) not applied; the fan helper is not ready.", source: "Fan")
            return
        }
        if afterWake {
            await refresh()
            guard FanControlPresentation.reportedPreset(snapshot, selectedPreset: nil) == .auto else { return }
        }
        send(saved)
        while isChanging { try? await Task.sleep(for: .milliseconds(100)) }
        LogManager.shared.info("Fan: saved \(saved.rawValue) applied again\(afterWake ? " after wake" : "").", source: "Fan")
    }

    private func manualControlLost(_ reason: String) {
        guard ownsManualControl else { return }
        ownsManualControl = false
        selectedPreset = nil
        errorMessage = reason
        LogManager.shared.warning("Fan: \(reason)", source: "Fan")
        Task { await refresh() }
    }

    /// `macpowertoys://fan/<auto|cool|max>`: applies a preset with no window, for tests and scripts. It never
    /// installs the helper, so it never shows a password prompt.
    func selectFromLink(_ preset: FanPreset) async {
        let owner = "deep-link"
        start(owner: owner)
        defer { stop(owner: owner) }
        await refresh()
        guard FanHelperService.shared.isEnabled else {
            LogManager.shared.warning("Fan link \(preset.rawValue) skipped: the fan helper is not installed or is outdated.",
                                      source: "Fan")
            return
        }
        select(preset)
        while isChanging { try? await Task.sleep(for: .milliseconds(100)) }
        let rpm = snapshot?.fans.map { Int($0.actualRPM ?? 0) } ?? []
        if let errorMessage {
            LogManager.shared.warning("Fan link \(preset.rawValue) failed: \(errorMessage)", source: "Fan")
        } else {
            LogManager.shared.info("Fan link \(preset.rawValue) applied, fans now \(rpm) RPM", source: "Fan")
        }
    }

    init(readSnapshot: @escaping @Sendable () -> FanSnapshot?,
         readTemperature: @escaping @Sendable () -> FanTemperatures? = { nil },
         applyPreset: @escaping @Sendable (FanPreset, @escaping @Sendable (String?) -> Void) -> Void = FanCommand.apply) {
        self.readSnapshot = readSnapshot
        self.readTemperature = readTemperature
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

    /// Tries the last chosen mode again. It asks for the password only when the helper is missing or older.
    func retry() {
        errorMessage = nil
        select(lastRequested ?? .auto)
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
        cpuCelsius = nil
        input = FanInput()
        lastTemperatureRead = nil
    }

    func refresh() async {
        let currentRevision = revision
        let readSnapshot = readSnapshot
        let readTemperature = readTemperature
        let (result, celsius) = await Task.detached(priority: .utility) { (readSnapshot(), readTemperature()) }.value
        guard currentRevision == revision, !owners.isEmpty, !isRestoringOnExit else { return }
        hasCompletedRead = true
        if let reading = celsius {
            let now = ContinuousClock.now
            input.update(reading, elapsed: lastTemperatureRead.map { (now - $0) / .seconds(1) } ?? 1)
            lastTemperatureRead = now
            inputName = input.driving?.name ?? FanInput.cpuName
            cpuCelsius = input.driving?.celsius
        }
        if let result {
            // A helper that is missing or older still allows a choice: the first write installs it.
            let helper = FanHelperService.shared
            let nativeControl = (helper.isEnabled || helper.canInstall || helper.status == .notResponding)
                && !result.fans.isEmpty
                && (!result.hasExternalManualControl || ownsManualControl)
                && result.fans.allSatisfy { ["auto", "manual", "system"].contains($0.mode ?? "") }
            snapshot = FanSnapshot(fans: result.fans, profile: result.profile,
                                   canControl: result.canControl || nativeControl)
        } else {
            snapshot = nil
        }
        if !ownsManualControl, !hasPendingManualCommand { selectedPreset = snapshot?.detectedPreset }
    }

    func select(_ preset: FanPreset) {
        guard !isRestoringOnExit else { return }
        guard FanControlPresentation.canSelect(preset, canControl: canControl,
                                              canRestoreAutomatic: canRestoreAutomatic, isChanging: isChanging) else { return }
        lastRequested = preset
        if !AppRuntime.isRunningTests { UserDefaults.standard.set(preset.rawValue, forKey: Self.savedPresetKey) }
        let helper = FanHelperService.shared
        guard !helper.isEnabled else { send(preset); return }
        // Auto while macOS already runs the fans needs no helper, so it never asks for a password.
        guard preset != .auto || snapshot?.hasExternalManualControl == true else { return }
        isChanging = true
        Task {
            if [.notResponding, .unknown].contains(helper.status) { await helper.refresh() }
            var message: String?
            if helper.canInstall {
                message = await helper.install()
            } else if !helper.isEnabled {
                message = "The fan helper did not answer. Click Retry."
            }
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
                    LogManager.shared.warning("Fan \(preset.rawValue) failed: \(commandError)", source: "Fan")
                } else {
                    self.ownsManualControl = preset != .auto
                    self.selectedPreset = preset
                }
                done?.resume(returning: commandError == nil)
                await self.refresh()
                guard currentCommand == self.commandRevision else { return }
                self.isChanging = false
            }
        }
    }

    func restoreAutomaticOnExit() async throws {
        guard !isRestoringOnExit else { throw FanError("Automatic fan restoration is already in progress.") }
        guard ownsManualControl || hasPendingManualCommand else { return }
        isRestoringOnExit = true
        revision &+= 1
        isChanging = true
        commandRevision &+= 1
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
            let cpuCelsius = cpuCelsius
            let inputName = inputName
            let next = await Task.detached(priority: .utility) {
                FanControlPresentation(snapshot: snapshot, selectedPreset: selectedPreset, errorMessage: errorMessage,
                                       canRestoreAutomatic: canRestoreAutomatic, canInstallHelper: canInstallHelper,
                                       isUnsupportedBuild: isUnsupportedBuild, isChanging: isChanging,
                                       hasCompletedRead: hasCompletedRead, cpuCelsius: cpuCelsius, inputName: inputName)
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
