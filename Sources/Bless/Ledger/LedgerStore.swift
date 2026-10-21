//
//  LedgerStore.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where a ledger's events are kept: append one, read them all, in order. In memory here;
//        FileLedgerStore keeps them as JSON lines.
//  PIN:  Synchronous on purpose: the Gate calls it inside actor methods that must not suspend,
//        so each transition and its ledger line happen as one step.
//

import Foundation
import Synchronization

public protocol LedgerStore: Sendable {
    func append(_ event: LedgerEvent) throws
    func all() throws -> [LedgerEvent]
}

public final class MemoryLedgerStore: LedgerStore {
    private let events = Mutex<[LedgerEvent]>([])

    public init() {}

    public func append(_ event: LedgerEvent) throws {
        events.withLock { $0.append(event) }
    }

    public func all() throws -> [LedgerEvent] {
        events.withLock { $0 }
    }
}
