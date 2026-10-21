//
//  SiteFixturesTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The fixtures the site's figures and Docs/INTEGRATION.md recompute: one petition's whole
//        life in a ledger (Fixtures/site/ledger.json) and one sealed amendment (seal.json), made
//        by the real Gate with a fixed clock, fixed ids and a fixed reviewer key. Run with
//        BLESS_WRITE_FIXTURES=1 to write them; every other run checks the files still match
//        what the code makes, so a figure can never drift from Bless's bytes.
//  PIN:  Ed25519 seals from CryptoKit are randomized, so the seal's signature is checked by
//        verifying it, and every other field byte for byte. The reviewer's private key is never
//        written; the fixture key is 32 bytes of 0x01, a test key.
//

import Foundation
import Testing
@testable import Bless

@Suite("Site fixtures")
struct SiteFixturesTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/site")
    static let writing = ProcessInfo.processInfo.environment["BLESS_WRITE_FIXTURES"] == "1"

    static let question = "Can I take ibuprofen with my lisinopril for a sore knee?"
    static let proposed = "Yes, ibuprofen is fine with lisinopril for a few days."
    static let amended = "Please avoid ibuprofen with lisinopril: together they can strain your kidneys. Take paracetamol instead, and call us if the knee still hurts in a week."

    struct LedgerFixture: Codable, Equatable {
        var about: String
        var texts: [String: String]
        var events: [LedgerEvent]
        /// Each event's canonical bytes, in hex, as the hash covers them.
        var canonical: [String]
    }

    struct SealFixture: Codable, Equatable {
        var about: String
        var verdict: Verdict
        var reviewer: Party
        var publicKey: String
        var canonical: String
        var signature: String
    }

    /// One petition's life at a fixed clock: held, viewed, amended (which blesses it at quorum 1), released.
    static func life() async throws -> (Gate, Verdict, ReviewerIdentity) {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_760_961_600))
        let gate = Gate(now: clock.now, sleeper: FakeClock.stalled, ids: { "p-7f3a" })
        let doctor = try ReviewerIdentity(id: "dr-okafor", displayName: "Dr. Okafor", privateKey: Data(repeating: 1, count: 32))
        let patient = Party(id: "patient-ada", displayName: "Ada")
        let draft = Draft(conversationID: "visit-0412", context: [.user(question)], proposed: .assistant(proposed),
                          provenance: Provenance(provider: "mistral", model: "mistral-small-latest", requestID: "cmpl-0412",
                                                 created: clock.current))
        let petition = try await gate.submit(draft, to: patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(4 * 3600), onLapse: .withhold))
        clock.advance(.seconds(95))
        try await gate.markViewed(petition.id, by: doctor.party.id)
        clock.advance(.seconds(140))
        let verdict = try doctor.verdict(.amend(content: amended), on: petition, note: "NSAID with an ACE inhibitor",
                                         issued: clock.current)
        try await gate.decide(verdict)
        clock.advance(.seconds(1))
        _ = try await gate.release(for: petition.id)
        return (gate, verdict, doctor)
    }

    static func made() async throws -> (LedgerFixture, SealFixture) {
        let (gate, verdict, doctor) = try await life()
        let events = try gate.ledger.events()
        let ledger = LedgerFixture(
            about: "One petition's life, written by Bless's Gate with a fixed clock (Tests/BlessTests/SiteFixturesTests.swift).",
            texts: ["question": question, "proposed": proposed, "amended": amended],
            events: events, canonical: events.map { $0.canonicalBytes.hexString })
        let seal = SealFixture(
            about: "One sealed amendment by a test key (32 bytes of 0x01), never a real reviewer's.",
            verdict: verdict, reviewer: doctor.party, publicKey: doctor.verifyingKey.hexString,
            canonical: verdict.canonicalBytes.hexString, signature: verdict.signature?.hexString ?? "")
        return (ledger, seal)
    }

    @Test("the ledger and seal fixtures are what the code makes today")
    func fixtures() async throws {
        let (ledger, seal) = try await Self.made()
        let encoder = JSONCoding.prettyEncoder()
        let ledgerURL = Self.folder.appendingPathComponent("ledger.json")
        let sealURL = Self.folder.appendingPathComponent("seal.json")
        if Self.writing {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try (encoder.encode(ledger) + Data("\n".utf8)).write(to: ledgerURL)
            try (encoder.encode(seal) + Data("\n".utf8)).write(to: sealURL)
        }
        let storedLedger = try JSONCoding.decoder().decode(LedgerFixture.self, from: Data(contentsOf: ledgerURL))
        #expect(storedLedger == ledger, "ledger.json is stale: run BLESS_WRITE_FIXTURES=1 swift test --filter SiteFixtures")
        #expect(try Ledger.verify(storedLedger.events) == 5)
        #expect(storedLedger.events.map(\.kind) == [.submitted, .viewed, .decided, .blessed, .released])

        let storedSeal = try JSONCoding.decoder().decode(SealFixture.self, from: Data(contentsOf: sealURL))
        #expect(storedSeal.canonical == seal.canonical, "seal.json is stale")
        #expect(storedSeal.publicKey == seal.publicKey)
        #expect(storedSeal.reviewer == seal.reviewer)
        #expect(Seal.verify(storedSeal.verdict, verifyingKey: Data(hexString: storedSeal.publicKey)))
        #expect(storedSeal.verdict.signature?.hexString == storedSeal.signature)
        #expect(storedSeal.verdict.canonicalBytes.hexString == storedSeal.canonical)
    }
}

extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
