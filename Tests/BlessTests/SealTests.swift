//
//  SealTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A reviewer's seal: it verifies under their key and no other, survives a JSON round trip,
//        and fails when any signed field changes.
//

import Foundation
import Testing
@testable import Bless

@Suite("Seal")
struct SealTests {
    let doctor = Fixture.reviewer(1)
    var verdict: Verdict {
        Verdict(petitionID: "p-1", reviewer: doctor.party.id, ruling: .amend(content: "Take it with food."),
                digest: .of("Take it."), note: "clearer", issued: Date(timeIntervalSince1970: 1_760_961_660))
    }

    @Test("a verdict signed by its reviewer verifies")
    func verifies() throws {
        let signed = try Seal.sign(verdict, privateKey: doctor.privateKey)
        #expect(signed.signature?.count == 64)
        #expect(Seal.verify(signed, verifyingKey: doctor.verifyingKey))
    }

    @Test("it still verifies after a JSON round trip")
    func roundTrip() throws {
        let signed = try Seal.sign(verdict, privateKey: doctor.privateKey)
        let back = try JSONCoding.decoder().decode(Verdict.self, from: try JSONCoding.encoder().encode(signed))
        #expect(back == signed)
        #expect(Seal.verify(back, verifyingKey: doctor.verifyingKey))
    }

    @Test("changing the text, the digest, the note or the time breaks the seal")
    func tamper() throws {
        let signed = try Seal.sign(verdict, privateKey: doctor.privateKey)
        let changed = [
            Verdict(petitionID: "p-1", reviewer: doctor.party.id, ruling: .amend(content: "Take it with water."),
                    digest: signed.digest, note: signed.note, issued: signed.issued, signature: signed.signature),
            Verdict(petitionID: "p-1", reviewer: doctor.party.id, ruling: signed.ruling, digest: .of("Take it!"),
                    note: signed.note, issued: signed.issued, signature: signed.signature),
            Verdict(petitionID: "p-1", reviewer: doctor.party.id, ruling: signed.ruling, digest: signed.digest,
                    note: nil, issued: signed.issued, signature: signed.signature),
            Verdict(petitionID: "p-1", reviewer: doctor.party.id, ruling: signed.ruling, digest: signed.digest,
                    note: signed.note, issued: signed.issued.addingTimeInterval(0.001), signature: signed.signature),
            Verdict(petitionID: "p-2", reviewer: doctor.party.id, ruling: signed.ruling, digest: signed.digest,
                    note: signed.note, issued: signed.issued, signature: signed.signature),
        ]
        for verdict in changed { #expect(!Seal.verify(verdict, verifyingKey: doctor.verifyingKey)) }
        var flipped = signed.signature!
        flipped[0] ^= 1
        let bad = Verdict(petitionID: "p-1", reviewer: doctor.party.id, ruling: signed.ruling, digest: signed.digest,
                          note: signed.note, issued: signed.issued, signature: flipped)
        #expect(!Seal.verify(bad, verifyingKey: doctor.verifyingKey))
    }

    @Test("another reviewer's key does not verify it; an unsigned verdict never verifies")
    func otherKey() throws {
        let signed = try Seal.sign(verdict, privateKey: doctor.privateKey)
        #expect(!Seal.verify(signed, verifyingKey: Fixture.reviewer(2).verifyingKey))
        #expect(!Seal.verify(verdict, verifyingKey: doctor.verifyingKey))
    }

    @Test("an identity rebuilt from its raw key has the same public key and fingerprint")
    func rebuilt() throws {
        let fresh = ReviewerIdentity(id: "dr-x", displayName: "Dr. X")
        let again = try ReviewerIdentity(id: "dr-x", displayName: "Dr. X", privateKey: fresh.privateKey)
        #expect(again.verifyingKey == fresh.verifyingKey)
        #expect(again.fingerprint == fresh.fingerprint)
        #expect(fresh.fingerprint.count == 16)
        #expect(throws: BlessError.self) { try ReviewerIdentity(id: "dr-x", displayName: "X", privateKey: Data(count: 5)) }
    }
}
