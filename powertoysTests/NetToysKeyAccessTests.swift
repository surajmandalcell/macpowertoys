import Foundation
import Testing
@testable import powertoys

@Suite("NetToys SSH key access")
struct NetToysKeyAccessTests {
    @Test("Dismissing password setup leaves a retry path")
    @MainActor
    func dismissalKeepsRetry() {
        let model = NetToysAnchorViewModel()
        let anchorID = UUID()
        model.pendingKeyAccessAnchorID = anchorID

        model.cancelKeyAccess()

        #expect(model.keyAccessRetryAnchorID == anchorID)
    }

    @Test("Public keys are reduced to one safe key line")
    func publicKeyValidation() throws {
        let key = try SSHPublicKey(
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA== comment with spaces"
        )

        #expect(key.line == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA==")
        #expect(throws: SSHPublicKey.Error.self) {
            try SSHPublicKey("command=bad ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA==")
        }
        #expect(throws: SSHPublicKey.Error.self) {
            try SSHPublicKey("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA==\nssh-rsa bad")
        }
    }

    @Test("Identity lookup expands home and keeps config order")
    func identityLookup() {
        let paths = SSHKeyAccessConfiguration.identityFilePaths(
            in: "identityfile ~/.ssh/id_ed25519\nidentityfile /tmp/second\n",
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )

        #expect(paths.map(\.path) == [
            "/Users/test/.ssh/id_ed25519",
            "/tmp/second",
        ])
    }

    @Test("Windows OpenSSH is detected from verbose output")
    func remoteKindDetection() {
        #expect(SSHRemoteKind.detect(in: "remote software version OpenSSH_for_Windows_9.5") == .windows)
        #expect(SSHRemoteKind.detect(in: "remote software version OpenSSH_10.3") == .unix)
        #expect(SSHRemoteKind.detect(in: "connection closed") == .unknown)
    }

    @Test("SSH arguments cannot reinterpret an alias as an option")
    func safeArguments() throws {
        #expect(try SSHKeyAccessConfiguration.checkArguments(alias: "win1").suffix(3) == [
            "--", "win1", "exit",
        ])
        #expect(throws: SSHKeyAccessError.self) {
            try SSHKeyAccessConfiguration.checkArguments(alias: "-oProxyCommand=bad")
        }
    }

    @Test("Windows command is static and round-trips through UTF-16LE")
    func windowsCommandEncoding() throws {
        let encoded = SSHKeyAccessConfiguration.windowsEncodedCommand
        let data = try #require(Data(base64Encoded: encoded))
        let script = try #require(String(data: data, encoding: .utf16LittleEndian))

        #expect(script.contains("administrators_authorized_keys"))
        #expect(script.contains("*S-1-5-32-544:F"))
        #expect(script.contains("[Console]::In.ReadLine()"))
        #expect(!script.contains("AAAAC3"))
        #expect(encoded.count < 6_000)
    }

    @Test("Askpass sends a dummy password once without storing it in the script")
    func askpassChannel() async throws {
        let channel = try SSHAskpassChannel()
        defer { channel.cleanup() }
        let delivery = channel.startDelivery(password: "dummy-password")

        let process = Process()
        let output = Pipe()
        process.executableURL = channel.scriptURL
        process.environment = channel.environment
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        _ = await delivery.result

        let value = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(process.terminationStatus == 0)
        #expect(value == "dummy-password\n")
        #expect(try String(contentsOf: channel.scriptURL, encoding: .utf8).contains("dummy-password") == false)
        #expect(channel.environment.values.contains(where: { $0.contains("dummy-password") }) == false)
        #expect(FileManager.default.fileExists(atPath: channel.fifoURL.path) == false)

        let secondProcess = Process()
        secondProcess.executableURL = channel.scriptURL
        secondProcess.environment = channel.environment
        secondProcess.standardOutput = FileHandle.nullDevice
        secondProcess.standardError = FileHandle.nullDevice
        try secondProcess.run()
        secondProcess.waitUntilExit()
        #expect(secondProcess.terminationStatus != 0)
    }
}
