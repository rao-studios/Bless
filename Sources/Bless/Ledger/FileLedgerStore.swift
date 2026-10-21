//
//  FileLedgerStore.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A ledger kept as a JSON-lines file: one event per line, appended and flushed to disk
//        before the append returns, readable by `jq` and by Ledger.verify from any language.
//        The file is the owner's only (0600), in a directory that is too (0700).
//

import Foundation
import Synchronization

public final class FileLedgerStore: LedgerStore {
    public let url: URL
    private let lock = Mutex<Void>(())

    public init(url: URL) throws {
        self.url = url
        try PrivateFile.createDirectory(url.deletingLastPathComponent())
        try PrivateFile.touch(url)
    }

    public func append(_ event: LedgerEvent) throws {
        var line = try JSONCoding.encoder().encode(event)
        line.append(0x0A)
        try lock.withLock { _ in try PrivateFile.append(line, to: url) }
    }

    public func all() throws -> [LedgerEvent] {
        let data = try lock.withLock { _ in try PrivateFile.read(url) }
        return try Ledger.events(fromJSONLines: data)
    }
}
