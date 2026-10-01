//
//  OrderedAtomicFileWriter.swift
//  powertoys
//

import Foundation

actor OrderedAtomicFileWriter {
    private var latestRevision = 0

    func write(_ data: Data, revision: Int, to url: URL) throws {
        guard revision > latestRevision else { return }
        try data.write(to: url, options: .atomic)
        latestRevision = revision
    }
}
