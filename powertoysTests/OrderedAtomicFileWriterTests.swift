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
        await writer.write(Data("current".utf8), revision: 2, to: url)
        await writer.write(Data("stale".utf8), revision: 1, to: url)

        XCTAssertEqual(try Data(contentsOf: url), Data("current".utf8))
    }
}
