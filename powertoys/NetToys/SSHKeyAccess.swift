import Darwin
import Foundation

nonisolated struct SSHPublicKey: Equatable, Sendable {
    enum Error: Swift.Error { case invalid }

    let line: String

    init(_ value: String) throws {
        guard !value.contains("\n"), !value.contains("\r") else { throw Error.invalid }
        let fields = value.split(whereSeparator: \Character.isWhitespace)
        guard fields.count >= 2 else { throw Error.invalid }
        let type = String(fields[0])
        let blob = String(fields[1])
        let allowedTypes = [
            "ssh-ed25519",
            "ssh-rsa",
            "ecdsa-sha2-nistp256",
            "ecdsa-sha2-nistp384",
            "ecdsa-sha2-nistp521",
            "sk-ssh-ed25519@openssh.com",
            "sk-ecdsa-sha2-nistp256@openssh.com",
        ]
        guard allowedTypes.contains(type),
              let decoded = Data(base64Encoded: blob), !decoded.isEmpty
        else { throw Error.invalid }
        line = "\(type) \(blob)"
    }
}

nonisolated enum SSHRemoteKind: Equatable, Sendable {
    case windows
    case unix
    case unknown

    static func detect(in diagnostics: String) -> Self {
        if diagnostics.localizedCaseInsensitiveContains("OpenSSH_for_Windows") { return .windows }
        if diagnostics.localizedCaseInsensitiveContains("remote software version OpenSSH_") { return .unix }
        return .unknown
    }
}

nonisolated enum SSHKeyAccessCheck: Equatable, Sendable {
    case ready
    case needsPassword(SSHRemoteKind)
}

nonisolated enum SSHKeyAccessError: LocalizedError {
    case unsafeAlias
    case noPublicKey
    case invalidPublicKey
    case passwordRejected
    case connectionFailed(String)
    case installFailed(String)
    case verificationFailed
    case timeout
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsafeAlias: "The SSH alias is not safe to pass to OpenSSH."
        case .noPublicKey: "No public key was found for this SSH host."
        case .invalidPublicKey: "The selected SSH public key is invalid."
        case .passwordRejected: "Windows did not accept the SSH password."
        case .connectionFailed(let message): message
        case .installFailed(let message): message
        case .verificationFailed:
            "The key was installed, but key-only login still failed. Check sshd_config and authorized_keys permissions."
        case .timeout: "SSH key setup timed out."
        case .processLaunchFailed(let message): "SSH could not start: \(message)"
        }
    }
}

nonisolated enum SSHKeyAccessConfiguration {
    static let sshURL = URL(fileURLWithPath: "/usr/bin/ssh")
    static let sshCopyIDURL = URL(fileURLWithPath: "/usr/bin/ssh-copy-id")

    static func checkArguments(alias: String) throws -> [String] {
        try validate(alias: alias)
        return [
            "-vv",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "--", alias, "exit",
        ]
    }

    static func windowsInstallArguments(alias: String) throws -> [String] {
        try validate(alias: alias)
        return [
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
            "-o", "ConnectTimeout=10",
            "-o", "LogLevel=ERROR",
            "--", alias,
            "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
            "-EncodedCommand", windowsEncodedCommand,
        ]
    }

    static func unixInstallArguments(alias: String, publicKeyURL: URL) throws -> [String] {
        try validate(alias: alias)
        return [
            "-i", publicKeyURL.path,
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
            alias,
        ]
    }

    static func identityFilePaths(in output: String, homeDirectory: URL) -> [URL] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            guard fields.count == 2, fields[0].lowercased() == "identityfile" else { return nil }
            var path = String(fields[1])
            if path.hasPrefix("~/") { path = homeDirectory.path + "/" + path.dropFirst(2) }
            if path.hasPrefix("%d/") { path = homeDirectory.path + "/" + path.dropFirst(3) }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    static let windowsScript = #"""
$ErrorActionPreference='Stop'
$k=[Console]::In.ReadLine()
if(-not $k){'MPT_RESULT error empty-key';exit 2}
$p=$k.Split(' ',3)
if($p.Count-lt 2){'MPT_RESULT error invalid-key';exit 2}
$b=$p[0]+' '+$p[1]
$e=New-Object Text.UTF8Encoding($false)
function Add-Key([string]$f){
  $d=Split-Path $f
  if(-not(Test-Path $d)){New-Item -ItemType Directory -Force $d|Out-Null}
  $t=if(Test-Path $f){[IO.File]::ReadAllText($f)}else{''}
  if(($t -split "`r?`n")|Where-Object{$_ -eq $b -or $_.StartsWith($b+' ')}){return}
  if($t.Length -gt 0 -and -not $t.EndsWith("`n")){$t+="`n"}
  [IO.File]::WriteAllText($f,$t+$b+"`n",$e)
}
$u=Join-Path $env:USERPROFILE '.ssh\authorized_keys'
Add-Key $u
$i=[Security.Principal.WindowsIdentity]::GetCurrent()
$a=(New-Object Security.Principal.WindowsPrincipal $i).IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')
if($a){
  $f=Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
  Add-Key $f
  & icacls.exe $f /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'|Out-Null
  if($LASTEXITCODE -ne 0){'MPT_RESULT error icacls';exit 3}
}
'MPT_RESULT ok '+$(if($a){'admin'}else{'user'})
"""#

    static let windowsEncodedCommand = windowsScript.data(using: .utf16LittleEndian)!.base64EncodedString()

    static func baseEnvironment() -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin",
            "LC_ALL": "C",
        ]
        if let socket = current["SSH_AUTH_SOCK"] { environment["SSH_AUTH_SOCK"] = socket }
        return environment
    }

    private static func validate(alias: String) throws {
        guard !alias.hasPrefix("-"), SSHConfigEditor.isSafeToken(alias) else {
            throw SSHKeyAccessError.unsafeAlias
        }
    }
}

nonisolated final class SSHAskpassChannel: @unchecked Sendable {
    let directoryURL: URL
    let scriptURL: URL
    let fifoURL: URL
    let environment: [String: String]

    init() throws {
        let fileManager = FileManager.default
        directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("macpowertoys-ssh-\(UUID().uuidString)", isDirectory: true)
        scriptURL = directoryURL.appendingPathComponent("askpass.sh")
        fifoURL = directoryURL.appendingPathComponent("password.fifo")
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let script = "#!/bin/sh\nIFS= read -r p < \"$MPT_ASKPASS_FIFO\" || exit 1\nprintf '%s\\n' \"$p\"\n"
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            guard mkfifo(fifoURL.path, S_IRUSR | S_IWUSR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
        var environment = SSHKeyAccessConfiguration.baseEnvironment()
        environment["DISPLAY"] = "macpowertoys"
        environment["SSH_ASKPASS"] = scriptURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["MPT_ASKPASS_FIFO"] = fifoURL.path
        self.environment = environment
    }

    func startDelivery(password: String) -> Task<Void, Never> {
        let path = fifoURL.path
        return Task.detached(priority: .userInitiated) {
            var bytes = Array(password.utf8) + [0x0a]
            defer {
                bytes.indices.forEach { bytes[$0] = 0 }
                unlink(path)
            }
            let deadline = Date().addingTimeInterval(45)
            while !Task.isCancelled, Date() < deadline {
                let descriptor = open(path, O_WRONLY | O_NONBLOCK)
                if descriptor >= 0 {
                    defer { close(descriptor) }
                    var written = 0
                    while written < bytes.count, !Task.isCancelled {
                        let count = bytes.withUnsafeBytes { buffer in
                            Darwin.write(
                                descriptor,
                                buffer.baseAddress!.advanced(by: written),
                                bytes.count - written
                            )
                        }
                        if count > 0 { written += count } else { break }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func cleanup() {
        unlink(fifoURL.path)
        try? FileManager.default.removeItem(at: directoryURL)
    }

    deinit { cleanup() }
}

private nonisolated struct SSHProcessResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

private nonisolated enum SSHProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = SSHKeyAccessConfiguration.baseEnvironment(),
        standardInput: Data? = nil,
        timeout: TimeInterval
    ) async throws -> SSHProcessResult {
        let worker = Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            let input = standardInput == nil ? nil : Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = output
            process.standardError = error
            process.standardInput = input
            do {
                try process.run()
            } catch {
                throw SSHKeyAccessError.processLaunchFailed(error.localizedDescription)
            }
            let outputReader = Task.detached {
                output.fileHandleForReading.readDataToEndOfFile()
            }
            let errorReader = Task.detached {
                error.fileHandleForReading.readDataToEndOfFile()
            }
            if let standardInput, let input {
                input.fileHandleForWriting.write(standardInput)
                try? input.fileHandleForWriting.close()
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, !Task.isCancelled, Date() < deadline {
                usleep(20_000)
            }
            let wasCancelled = Task.isCancelled
            let timedOut = process.isRunning && Date() >= deadline
            if process.isRunning {
                process.terminate()
                let killDeadline = Date().addingTimeInterval(2)
                while process.isRunning, Date() < killDeadline {
                    usleep(20_000)
                }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            let outputData = await outputReader.value
            let errorData = await errorReader.value
            if wasCancelled { throw CancellationError() }
            if timedOut { throw SSHKeyAccessError.timeout }
            return SSHProcessResult(
                status: process.terminationStatus,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

nonisolated enum SSHKeyAccessInstaller {
    static func check(alias: String) async throws -> SSHKeyAccessCheck {
        let result = try await SSHProcessRunner.run(
            executableURL: SSHKeyAccessConfiguration.sshURL,
            arguments: SSHKeyAccessConfiguration.checkArguments(alias: alias),
            timeout: 10
        )
        if result.status == 0 { return .ready }
        if result.standardError.localizedCaseInsensitiveContains("Permission denied") {
            return .needsPassword(SSHRemoteKind.detect(in: result.standardError))
        }
        throw SSHKeyAccessError.connectionFailed(connectionMessage(result.standardError))
    }

    static func install(alias: String, password: String, remoteKind: SSHRemoteKind) async throws {
        guard !password.isEmpty else { throw SSHKeyAccessError.passwordRejected }
        let identity = try await loadIdentity(alias: alias)
        let channel = try SSHAskpassChannel()
        let delivery = channel.startDelivery(password: password)
        let result: SSHProcessResult
        do {
            switch remoteKind {
            case .windows:
                result = try await SSHProcessRunner.run(
                    executableURL: SSHKeyAccessConfiguration.sshURL,
                    arguments: SSHKeyAccessConfiguration.windowsInstallArguments(alias: alias),
                    environment: channel.environment,
                    standardInput: Data((identity.key.line + "\n").utf8),
                    timeout: 45
                )
            case .unix, .unknown:
                result = try await SSHProcessRunner.run(
                    executableURL: SSHKeyAccessConfiguration.sshCopyIDURL,
                    arguments: SSHKeyAccessConfiguration.unixInstallArguments(
                        alias: alias,
                        publicKeyURL: identity.publicKeyURL
                    ),
                    environment: channel.environment,
                    timeout: 45
                )
            }
        } catch {
            delivery.cancel()
            _ = await delivery.result
            channel.cleanup()
            throw error
        }
        delivery.cancel()
        _ = await delivery.result
        channel.cleanup()
        guard result.status == 0 else {
            if result.standardError.localizedCaseInsensitiveContains("Permission denied") {
                throw SSHKeyAccessError.passwordRejected
            }
            if result.standardOutput.contains("MPT_RESULT error icacls") {
                throw SSHKeyAccessError.installFailed(
                    "Windows could not secure administrators_authorized_keys."
                )
            }
            throw SSHKeyAccessError.installFailed("The SSH public key could not be installed.")
        }
        guard try await check(alias: alias) == .ready else {
            throw SSHKeyAccessError.verificationFailed
        }
    }

    private static func loadIdentity(alias: String) async throws -> (key: SSHPublicKey, publicKeyURL: URL) {
        let result = try await SSHProcessRunner.run(
            executableURL: SSHKeyAccessConfiguration.sshURL,
            arguments: ["-G", "--", alias],
            timeout: 5
        )
        guard result.status == 0 else { throw SSHKeyAccessError.noPublicKey }
        let fileManager = FileManager.default
        let paths = SSHKeyAccessConfiguration.identityFilePaths(
            in: result.standardOutput,
            homeDirectory: fileManager.homeDirectoryForCurrentUser
        )
        for path in paths {
            let publicKeyURL = URL(fileURLWithPath: path.path + ".pub")
            guard let value = try? String(contentsOf: publicKeyURL, encoding: .utf8) else { continue }
            do {
                return (try SSHPublicKey(value.trimmingCharacters(in: .whitespacesAndNewlines)), publicKeyURL)
            } catch {
                throw SSHKeyAccessError.invalidPublicKey
            }
        }
        throw SSHKeyAccessError.noPublicKey
    }

    private static func connectionMessage(_ diagnostics: String) -> String {
        if diagnostics.localizedCaseInsensitiveContains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
            return "The remote SSH host key changed. SSH Anchor will not bypass this warning."
        }
        if diagnostics.localizedCaseInsensitiveContains("Connection refused") {
            return "The SSH service refused the connection."
        }
        if diagnostics.localizedCaseInsensitiveContains("timed out") {
            return "The SSH connection timed out."
        }
        return "The SSH host could not be reached."
    }
}
