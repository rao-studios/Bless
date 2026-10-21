//
//  Ledger.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The append-only, hash-chained audit log of every petition's life. `append` numbers the
//        event, links it to the last hash and writes it; `verify` walks the chain and names the
//        first event that does not fit (a changed byte, a dropped line, a swapped pair).
//        `jsonLines()` exports it; `Ledger.verify(_:)` checks an export on its own.
//  PIN:  The first event's `previous` is 32 zero bytes; seq starts at 1. A Ledger reopened over
//        a file picks up the chain where it ended.
//

import Foundation
import Synchronization

public final class Ledger: Sendable {
    private struct Head: Sendable {
        var seq: Int
        var hash: Sha256
    }

    private let store: any LedgerStore
    private let head: Mutex<Head>

    /// A ledger in memory.
    public init() {
        self.store = MemoryLedgerStore()
        self.head = Mutex(Head(seq: 0, hash: .zero))
    }

    /// A ledger over a store, continuing whatever chain it holds.
    public init(store: any LedgerStore) throws {
        self.store = store
        let last = try store.all().last
        self.head = Mutex(Head(seq: last?.seq ?? 0, hash: last?.hash ?? .zero))
    }

    /// Writes the next event and returns it.
    @discardableResult
    public func append(_ kind: LedgerEvent.Kind, petition: Petition.ID, actor: Party.ID? = nil, digest: Sha256? = nil,
                       code: String? = nil, at: Date) throws -> LedgerEvent {
        try head.withLock { head in
            let event = LedgerEvent(seq: head.seq + 1, at: at, kind: kind, petitionID: petition, actor: actor,
                                    digest: digest, code: code, previous: head.hash)
            try store.append(event)
            head = Head(seq: event.seq, hash: event.hash)
            return event
        }
    }

    /// Every event, oldest first.
    public func events() throws -> [LedgerEvent] {
        try store.all()
    }

    /// The events concerning one petition.
    public func events(for petition: Petition.ID) throws -> [LedgerEvent] {
        try store.all().filter { $0.petitionID == petition }
    }

    /// The number of events, or `.ledgerTampered(seq:)` at the first that breaks the chain.
    @discardableResult
    public func verify() throws -> Int {
        try Self.verify(try store.all())
    }

    /// The same check over events from anywhere (an export, another store).
    @discardableResult
    public static func verify(_ events: [LedgerEvent]) throws -> Int {
        var previous = Sha256.zero
        for (index, event) in events.enumerated() {
            let expected = index + 1
            guard event.seq == expected else { throw BlessError.ledgerTampered(seq: expected) }
            guard event.previous == previous, event.hash == event.recomputedHash else {
                throw BlessError.ledgerTampered(seq: event.seq)
            }
            previous = event.hash
        }
        return events.count
    }

    /// The ledger as JSON lines, one event per line.
    public func jsonLines() throws -> Data {
        let encoder = JSONCoding.encoder()
        var out = Data()
        for event in try store.all() {
            out.append(try encoder.encode(event))
            out.append(0x0A)
        }
        return out
    }

    /// Events from JSON lines (blank lines are skipped).
    public static func events(fromJSONLines data: Data) throws -> [LedgerEvent] {
        let decoder = JSONCoding.decoder()
        return try data.split(separator: 0x0A).filter { !$0.allSatisfy { $0 == 0x20 || $0 == 0x0D } }.map {
            try decoder.decode(LedgerEvent.self, from: Data($0))
        }
    }
}
