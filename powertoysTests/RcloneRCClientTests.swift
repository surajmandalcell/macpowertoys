import XCTest
@testable import powertoys

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

    private static func response(for request: URLRequest, json: [String: Any]) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
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
