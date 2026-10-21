//
//  LedgerTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The audit log: each event chained to the last, any change named by its seq, no content
//        or free text written, and a file ledger that is private and picks up where it ended.
//

import Foundation
import Testing
@testable import Bless

@Suite("Ledger")
struct LedgerTests {
    static let t0 = Date(timeIntervalSince1970: 1_760_961_600)

    func filled(_ ledger: Ledger, count: Int = 5) throws {
        for n in 1...count {
            try ledger.append(n == 1 ? .submitted : .decided, petition: "p-1", actor: n == 1 ? nil : "dr-1",
                              digest: .of("text \(n)"), code: n == 1 ? nil : "bless", at: Self.t0.addingTimeInterval(Double(n)))
        }
    }

    @Test("each event's previous is the last hash; the first is zero")
    func chained() throws {
        let ledger = Ledger()
        try filled(ledger)
        let events = try ledger.events()
        #expect(events[0].previous == .zero)
        for (a, b) in zip(events, events.dropFirst()) { #expect(b.previous == a.hash) }
        #expect(try ledger.verify() == 5)
    }

    @Test("verify names the event where a byte changed, a line went missing, or two swapped")
    func tamper() throws {
        let ledger = Ledger()
        try filled(ledger)
        let events = try ledger.events()
        let lines = String(decoding: try ledger.jsonLines(), as: UTF8.self).split(separator: "\n").map(String.init)
        var changed = lines
        changed[2] = changed[2].replacingOccurrences(of: "\"code\":\"bless\"", with: "\"code\":\"withhold\"")
        let edited = try Ledger.events(fromJSONLines: Data(changed.joined(separator: "\n").utf8))
        #expect(throws: BlessError.ledgerTampered(seq: 3)) { try Ledger.verify(edited) }
        #expect(throws: BlessError.ledgerTampered(seq: 2)) { try Ledger.verify(Array(events[0..<1] + events[2...])) }
        #expect(throws: BlessError.ledgerTampered(seq: 2)) { try Ledger.verify([events[0], events[2], events[1]] + events[3...]) }
        #expect(try Ledger.verify(Array(events.prefix(3))) == 3)
    }

    @Test("a ledger holds ids, digests and codes; a withholding's reason never reaches it")
    func noContent() async throws {
        let gate = Fixture.gate()
        let doctor = Fixture.reviewer(1)
        let secret = "positive for strep, call before noon"
        let petition = try await gate.submit(Fixture.draft("Your result is in."), to: Fixture.patient, reviewers: [doctor.party])
        try await gate.decide(petition.id, .withhold(reason: secret), as: doctor)
        let log = String(decoding: try gate.ledger.jsonLines(), as: UTF8.self)
        #expect(!log.contains("strep"))
        #expect(!log.contains("Your result"))
        #expect(!log.contains("amoxicillin"))
        #expect(log.contains(Sha256.of("Your result is in.").hex))
    }

    @Test("a file ledger writes 0600 JSON lines in a 0700 directory and reads them back")
    func fileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bless-ledger-\(UUID())/audit")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let url = dir.appendingPathComponent("ledger.jsonl")
        let ledger = try Ledger(store: FileLedgerStore(url: url))
        try filled(ledger, count: 3)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let dirAttributes = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((dirAttributes[.posixPermissions] as? Int) == 0o700)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 3)
        #expect(try ledger.events() == (try Ledger.events(fromJSONLines: Data(text.utf8))))
    }

    @Test("a ledger reopened over its file continues the chain")
    func reopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bless-ledger-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.jsonl")
        try filled(try Ledger(store: FileLedgerStore(url: url)), count: 2)
        let again = try Ledger(store: FileLedgerStore(url: url))
        let third = try again.append(.released, petition: "p-1", digest: .of("text 2"), code: "blessed", at: Self.t0)
        #expect(third.seq == 3)
        #expect(try again.verify() == 3)
    }
}
