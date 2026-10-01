//
//  OrderedAtomicFileWriterTests.swift
//  powertoysTests
//

import Foundation
import XCTest
@testable import powertoys

final class OrderedAtomicFileWriterTests: XCTestCase {
    func testLateOlderWriteCannotReplaceNewerContents() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ordered-file-writer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = OrderedAtomicFileWriter()
        try await writer.write(Data("current".utf8), revision: 2, to: url)
        try await writer.write(Data("stale".utf8), revision: 1, to: url)

        XCTAssertEqual(try Data(contentsOf: url), Data("current".utf8))
    }

    func testFailedWriteThrowsAndAllowsSameRevisionRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("transfers.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = OrderedAtomicFileWriter()
        do {
            try await writer.write(Data("resume".utf8), revision: 1, to: url)
            XCTFail("A missing parent must report the write failure")
        } catch {}
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await writer.write(Data("resume".utf8), revision: 1, to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data("resume".utf8))
    }
}
