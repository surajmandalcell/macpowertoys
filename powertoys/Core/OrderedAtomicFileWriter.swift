//
//  OrderedAtomicFileWriter.swift
//  powertoys
//

import Foundation

actor OrderedAtomicFileWriter {
    private var latestRevision = 0

    func write(_ data: Data, revision: Int, to url: URL) {
        guard revision > latestRevision else { return }
        latestRevision = revision
        try? data.write(to: url, options: .atomic)
    }
}
