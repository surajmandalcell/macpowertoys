import XCTest
@testable import powertoys

@MainActor
final class RcloneRCClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testAuthenticatedRequestUsesBasicAuthorization() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic bWFjOnNlY3JldA==")
            return Self.response(for: request, json: ["version": "1.72.0"])
        }

        let client = makeClient(credentials: .init(username: "mac", password: "secret"))
        let version = try await client.version()
        XCTAssertEqual(version, "1.72.0")
    }

    func testProviderDiscoveryDecodesRcloneSchema() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/config/providers")
            return Self.response(for: request, json: [
                "providers": [[
                    "Name": "drive",
                    "Description": "Google Drive",
                    "Prefix": "drive",
                    "Options": [[
                        "Name": "client_id",
                        "FieldName": "client_id",
                        "Help": "OAuth Client Id.",
                        "Type": "string",
                        "Required": false,
                        "IsPassword": false,
                        "Advanced": false,
                        "Hide": 0,
                        "Default": "",
                        "Examples": [["Value": "", "Help": "Use rclone's client ID"]]
                    ]]
                ]]
            ])
        }

        let providers = try await makeClient().providers()

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers[0].id, "drive")
        XCTAssertEqual(providers[0].displayName, "Google Drive")
        XCTAssertEqual(providers[0].options[0].name, "client_id")
        XCTAssertEqual(providers[0].options[0].examples.first?.help, "Use rclone's client ID")
        XCTAssertFalse(providers[0].options[0].usesExclusivePicker)
    }

    func testConfigurationStepUsesNonInteractiveProtocol() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/config/create")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let opt = try XCTUnwrap(json["opt"] as? [String: Any])
            XCTAssertEqual(json["name"] as? String, "archive")
            XCTAssertEqual(json["type"] as? String, "drive")
            XCTAssertEqual(opt["nonInteractive"] as? Bool, true)
            XCTAssertNil(opt["all"], "the form already collects provider options; rclone should only ask post-config questions")
            return Self.response(for: request, json: [
                "State": "*oauth-islocal,teamdrive,,",
                "Option": [
                    "Name": "config_is_local",
                    "Help": "Use a browser on this Mac?",
                    "Type": "bool",
                    "Default": true,
                    "Required": false,
                    "IsPassword": false,
                    "Exclusive": true,
                    "Examples": [
                        ["Value": "true", "Help": "Yes"],
                        ["Value": "false", "Help": "No"]
                    ]
                ],
                "Error": ""
            ])
        }

        let step = try await makeClient().beginConfiguration(
            name: "archive",
            type: "drive",
            parameters: ["scope": "drive"]
        )

        XCTAssertFalse(step.isComplete)
        XCTAssertEqual(step.state, "*oauth-islocal,teamdrive,,")
        XCTAssertEqual(step.option?.name, "config_is_local")
        XCTAssertEqual(step.option?.examples.map(\.value), ["true", "false"])
        XCTAssertTrue(step.option?.usesExclusivePicker == true)
    }

    func testConfigurationContinuationPreservesStateAndParameters() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/config/update")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let opt = try XCTUnwrap(json["opt"] as? [String: Any])
            let parameters = try XCTUnwrap(json["parameters"] as? [String: String])
            XCTAssertEqual(json["name"] as? String, "archive")
            XCTAssertEqual(parameters["scope"], "drive")
            XCTAssertEqual(opt["nonInteractive"] as? Bool, true)
            XCTAssertEqual(opt["continue"] as? Bool, true)
            XCTAssertEqual(opt["state"] as? String, "oauth-state")
            XCTAssertEqual(opt["result"] as? String, "true")
            return Self.response(for: request, json: ["State": "", "Error": ""])
        }

        let step = try await makeClient().continueConfiguration(
            name: "archive",
            parameters: ["scope": "drive"],
            state: "oauth-state",
            result: "true"
        )

        XCTAssertTrue(step.isComplete)
        XCTAssertEqual(step.error, "")
    }

    func testProviderOptionDecodesPasswordAdvancedAndNumericDefaults() async throws {
        URLProtocolStub.handler = { request in
            Self.response(for: request, json: [
                "providers": [[
                    "Name": "sftp",
                    "Description": "SFTP",
                    "Options": [[
                        "Name": "pass",
                        "FieldName": "pass",
                        "Type": "string",
                        "Default": 22,
                        "Required": true,
                        "IsPassword": true,
                        "Advanced": true,
                        "Hide": 0,
                        "Exclusive": false
                    ]]
                ]]
            ])
        }

        let providers = try await makeClient().providers()
        let option = try XCTUnwrap(providers.first?.options.first)

        XCTAssertEqual(option.defaultValue, "22")
        XCTAssertTrue(option.required)
        XCTAssertTrue(option.isPassword)
        XCTAssertTrue(option.advanced)
        XCTAssertFalse(option.hidden)
    }

    func testHealthRemoteAndCapacityResponsesDecodeNumericShapes() async throws {
        var paths: [String] = []
        URLProtocolStub.handler = { request in
            paths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/rc/noop":
                return Self.response(for: request, json: [:])
            case "/config/listremotes":
                return Self.response(for: request, json: ["remotes": ["archive:", "photos:"]])
            case "/config/dump":
                return Self.response(for: request, json: [
                    "archive": ["type": "s3"],
                    "photos": ["type": "drive"],
                    "invalid": "not-a-dictionary"
                ])
            case "/operations/about":
                return Self.response(for: request, json: ["total": 1_000, "used": 250.0, "free": 750])
            default:
                XCTFail("Unexpected path: \(request.url?.path ?? "nil")")
                return Self.response(for: request, json: [:])
            }
        }

        let client = makeClient()
        try await client.ping()
        let remotes = try await client.listRemotes()
        let types = try await client.remoteTypes()
        XCTAssertEqual(remotes, ["archive:", "photos:"])
        XCTAssertEqual(types, ["archive": "s3", "photos": "drive"])
        let capacity = try await client.about(fs: "archive:")
        XCTAssertEqual(capacity.total, 1_000)
        XCTAssertEqual(capacity.used, 250)
        XCTAssertEqual(capacity.free, 750)
        XCTAssertEqual(paths, ["/rc/noop", "/config/listremotes", "/config/dump", "/operations/about"])
    }

    func testProvidersSortByDescriptionAndRejectMissingSchema() async throws {
        URLProtocolStub.handler = { request in
            Self.response(for: request, json: [
                "providers": [
                    ["Name": "z-local", "Description": "Alpha Local"],
                    ["Name": "a-cloud", "Description": "Zulu Cloud"],
                    ["Description": "Missing name"]
                ]
            ])
        }
        let providerNames = try await makeClient().providers().map(\.name)
        XCTAssertEqual(providerNames, ["z-local", "a-cloud"])

        URLProtocolStub.handler = { request in Self.response(for: request, json: [:]) }
        do {
            _ = try await makeClient().providers()
            XCTFail("Expected a schema error")
        } catch let error as RcloneRCError {
            XCTAssertEqual(error.errorDescription, "Unexpected response from rclone: missing providers")
        }
    }

    func testStartJobBuildsConfigAndFilterAndAcceptsNumericJobID() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/sync/copy")
            let body = try Self.body(for: request)
            XCTAssertEqual(body["srcFs"] as? String, "/source")
            XCTAssertEqual(body["dstFs"] as? String, "archive:backup")
            XCTAssertEqual(body["_async"] as? Bool, true)
            XCTAssertEqual(body["_group"] as? String, "job/one")
            XCTAssertEqual((body["_config"] as? [String: Any])?["Transfers"] as? Int, 8)
            XCTAssertEqual((body["_filter"] as? [String: Any])?["ExcludeRule"] as? [String], ["*.tmp"])
            return Self.response(for: request, json: ["jobid": 42.0])
        }

        let id = try await makeClient().startJob(
            endpoint: "sync/copy",
            srcFs: "/source",
            dstFs: "archive:backup",
            group: "job/one",
            excludePatterns: ["*.tmp"],
            config: ["Transfers": 8]
        )
        XCTAssertEqual(id, 42)
    }

    func testMissingJobIDReturnsDecodingError() async throws {
        URLProtocolStub.handler = { request in Self.response(for: request, json: [:]) }
        do {
            _ = try await makeClient().startSizeJob(fs: "/source", excludePatterns: [])
            XCTFail("Expected a missing job ID error")
        } catch let error as RcloneRCError {
            XCTAssertEqual(error.errorDescription, "Unexpected response from rclone: missing jobid")
        }
    }

    func testDirectoryListingSkipsMalformedRowsSortsFoldersAndParsesDates() async throws {
        URLProtocolStub.handler = { request in
            let body = try Self.body(for: request)
            XCTAssertEqual((body["opt"] as? [String: Any])?["recurse"] as? Bool, true)
            return Self.response(for: request, json: ["list": [
                ["Path": "z.txt", "Size": 12.0, "ModTime": "2026-07-13T10:20:30Z", "MimeType": "text/plain"],
                ["Path": "folder", "Name": "Folder", "IsDir": true],
                ["Name": "missing path"]
            ]])
        }

        let entries = try await makeClient().listDirectory(fs: "archive:", remote: "", recurse: true)
        XCTAssertEqual(entries.map(\.name), ["Folder", "z.txt"])
        XCTAssertTrue(entries[0].isDir)
        XCTAssertEqual(entries[1].size, 12)
        XCTAssertNotNil(entries[1].modTime)
    }

    func testCopyFileAndMaintenanceCommandsSendExpectedBodies() async throws {
        var calls: [(String, [String: Any])] = []
        URLProtocolStub.handler = { request in
            let body = try Self.body(for: request)
            calls.append((request.url?.path ?? "", body))
            return Self.response(for: request, json: request.url?.path == "/operations/copyfile" ? ["jobid": 8] : [:])
        }

        let client = makeClient()
        let jobID = try await client.startCopyFileJob(
            srcFs: "source:", srcRemote: "one.txt", dstFs: "dest:", dstRemote: "two.txt", group: "job/file", config: ["Checkers": 3]
        )
        XCTAssertEqual(jobID, 8)
        try await client.stopJob(jobid: 8)
        try await client.setBandwidthLimit("5M")
        try await client.deleteFile(fs: "dest:", remote: "two.txt")
        try await client.purgeDirectory(fs: "dest:", remote: "folder")
        try await client.deleteRemoteConfig(name: "unused")

        XCTAssertEqual(calls.map(\.0), [
            "/operations/copyfile", "/job/stop", "/core/bwlimit", "/operations/deletefile", "/operations/purge", "/config/delete"
        ])
        XCTAssertEqual(calls[0].1["srcRemote"] as? String, "one.txt")
        XCTAssertEqual((calls[0].1["_config"] as? [String: Any])?["Checkers"] as? Int, 3)
        XCTAssertEqual(calls[1].1["jobid"] as? Int, 8)
        XCTAssertEqual(calls[2].1["rate"] as? String, "5M")
        XCTAssertEqual(calls[5].1["name"] as? String, "unused")
    }

    func testJobStatusAndStatsDecodeMixedNumericRepresentations() async throws {
        URLProtocolStub.handler = { request in
            switch request.url?.path {
            case "/job/status":
                return Self.response(for: request, json: [
                    "finished": true, "success": true, "duration": 2.5,
                    "output": ["bytes": 1_024.0, "count": 3.0]
                ])
            case "/core/stats":
                return Self.response(for: request, json: [
                    "bytes": 500.0, "totalBytes": 1_000, "speed": 25,
                    "eta": 20, "errors": 1.0, "checks": 2, "totalChecks": 4.0,
                    "transfers": 3, "totalTransfers": 6.0, "elapsedTime": 10,
                    "fatalError": false, "retryError": true, "lastError": "temporary",
                    "transferring": [[
                        "name": "large.mov", "size": 1_000.0, "bytes": 250,
                        "percentage": 25.0, "speed": 20, "speedAvg": 18.5, "eta": 37
                    ], ["size": 1]]
                ])
            default:
                return Self.response(for: request, json: [:])
            }
        }

        let client = makeClient()
        let status = try await client.jobStatus(jobid: 7)
        XCTAssertTrue(status.finished)
        XCTAssertTrue(status.success)
        XCTAssertEqual(status.outputBytes, 1_024)
        XCTAssertEqual(status.outputCount, 3)

        let stats = try await client.stats(group: "job/one")
        XCTAssertEqual(stats.bytes, 500)
        XCTAssertEqual(stats.totalBytes, 1_000)
        XCTAssertEqual(stats.speed, 25)
        XCTAssertEqual(stats.eta, 20)
        XCTAssertEqual(stats.errors, 1)
        XCTAssertEqual(stats.transferring.count, 1)
        XCTAssertEqual(stats.transferring[0].speedAvg, 18.5)
        XCTAssertEqual(stats.lastError, "temporary")
        XCTAssertTrue(stats.retryError)
    }

    func testHTTPAndTransportFailuresMapToStableErrors() async throws {
        URLProtocolStub.handler = { request in
            Self.response(for: request, status: 401, json: ["error": "bad credentials"])
        }
        do {
            try await makeClient().ping()
            XCTFail("Expected HTTP failure")
        } catch let error as RcloneRCError {
            XCTAssertEqual(error.errorDescription, "bad credentials")
        }

        URLProtocolStub.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            try await makeClient().ping()
            XCTFail("Expected reachability failure")
        } catch let error as RcloneRCError {
            XCTAssertEqual(error.errorDescription, "The rclone daemon is not reachable.")
        }
    }

    private func makeClient(credentials: RcloneRCCredentials? = nil) -> RcloneRCClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return RcloneRCClient(
            baseURL: URL(string: "http://127.0.0.1:5572")!,
            credentials: credentials,
            session: URLSession(configuration: configuration)
        )
    }

    private static func body(for request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func response(for request: URLRequest, status: Int = 200, json: [String: Any]) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, try! JSONSerialization.data(withJSONObject: json))
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
