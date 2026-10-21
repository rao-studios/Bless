//
//  CanonicalTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The bytes a seal signs and a ledger hash covers, held to golden vectors. The vectors
//        were computed by an independent Python implementation of the layout (the one
//        Docs/INTEGRATION.md shows), so these tests also prove a second language can reproduce
//        Bless's bytes.
//

import Foundation
import Testing
@testable import Bless

@Suite("Canonical bytes")
struct CanonicalTests {
    static let text = "Take it with food, twice a day."
    static let issued = Date(timeIntervalSince1970: 1_760_961_660)

    @Test("the writer lays out strings, optionals, int64 and digests as documented")
    func writer() {
        var writer = Canonical.Writer()
        writer.string("ab")
        writer.optional(nil as String?)
        writer.optional("c")
        writer.int64(-2)
        writer.optional(nil as Sha256?)
        #expect(writer.data.hexString == "00000002616200010000000163fffffffffffffffe00")
    }

    @Test("a content digest is SHA-256 of the UTF-8 bytes, exactly as given")
    func contentDigest() {
        #expect(Sha256.of("hello").hex == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(Sha256.of(Self.text).hex == "f7a9805dd73aa78797a27d268b455369338cb69c3fce2a2b3ffafbf161d1bc0d")
        #expect(Sha256.of("Take it with food, twice a day. ") != Sha256.of(Self.text))
    }

    @Test("a blessing's canonical bytes match the golden vector")
    func blessingBytes() {
        let verdict = Verdict(petitionID: "p-1", reviewer: "dr-1", ruling: .bless, digest: .of(Self.text), issued: Self.issued)
        #expect(verdict.canonicalBytes.hexString == "0000000f626c6573732f766572646963742f3100000003702d310000000464722d3100000005626c657373f7a9805dd73aa78797a27d268b455369338cb69c3fce2a2b3ffafbf161d1bc0d000000019a017e8460")
    }

    @Test("an amendment's canonical bytes carry its text and note, and match the golden vector")
    func amendmentBytes() {
        let verdict = Verdict(petitionID: "p-1", reviewer: "dr-1",
                              ruling: .amend(content: "Take it with food, twice a day, for all 7 days."),
                              digest: .of(Self.text), note: "finish the course", issued: Self.issued)
        #expect(verdict.canonicalBytes.hexString == "0000000f626c6573732f766572646963742f3100000003702d310000000464722d3100000005616d656e640000002f54616b65206974207769746820666f6f642c2074776963652061206461792c20666f7220616c6c203720646179732ef7a9805dd73aa78797a27d268b455369338cb69c3fce2a2b3ffafbf161d1bc0d010000001166696e6973682074686520636f757273650000019a017e8460")
    }

    @Test("a ledger's first two events hash to the golden vectors")
    func eventHashes() throws {
        let ledger = Ledger()
        let first = try ledger.append(.submitted, petition: "p-1", digest: .of(Self.text), at: Date(timeIntervalSince1970: 1_760_961_600))
        #expect(first.canonicalBytes.hexString == "0000000d626c6573732f6576656e742f3100000000000000010000019a017d9a00000000097375626d697474656400000003702d310001f7a9805dd73aa78797a27d268b455369338cb69c3fce2a2b3ffafbf161d1bc0d000000000000000000000000000000000000000000000000000000000000000000")
        #expect(first.hash.hex == "4c73c3a069fd907f314e0c5e0b35893dfaf8a38b2b8764b1be9b0d7e3db993f2")
        let second = try ledger.append(.decided, petition: "p-1", actor: "dr-1", digest: .of(Self.text), code: "bless", at: Self.issued)
        #expect(second.previous == first.hash)
        #expect(second.hash.hex == "4453958e635139ab3152b210cb3e1562799fd742bd8239aebfabe8da2dec98db")
    }

    @Test("Sha256 is lowercase hex in JSON and round-trips; other lengths are refused")
    func sha256Coding() throws {
        let digest = Sha256.of("x")
        let json = try JSONCoding.encoder().encode([digest])
        #expect(String(decoding: json, as: UTF8.self) == "[\"\(digest.hex)\"]")
        #expect(try JSONCoding.decoder().decode([Sha256].self, from: json) == [digest])
        #expect(Sha256(hex: digest.hex.uppercased()) == digest)
        #expect(Sha256(hex: "abc") == nil)
        #expect(Sha256(bytes: Data(count: 31)) == nil)
        #expect(Sha256.zero.hex == String(repeating: "0", count: 64))
    }

    @Test("stamps are whole milliseconds and survive JSON exactly")
    func stamps() throws {
        let raw = Date(timeIntervalSince1970: 1_760_961_600.123_456_7)
        let stamped = Canonical.stamp(raw)
        #expect(Canonical.milliseconds(stamped) == 1_760_961_600_123)
        struct Box: Codable, Equatable { var at: Date }
        let json = try JSONCoding.encoder().encode(Box(at: stamped))
        #expect(String(decoding: json, as: UTF8.self) == "{\"at\":1760961600123}")
        let back = try JSONCoding.decoder().decode(Box.self, from: json)
        #expect(Canonical.milliseconds(back.at) == 1_760_961_600_123)
        #expect(Canonical.stamp(back.at) == back.at)
    }

    @Test("JSONCoding sorts keys")
    func sortedKeys() throws {
        let json = try JSONCoding.encoder().encode(["b": 1, "a": 2])
        #expect(String(decoding: json, as: UTF8.self) == "{\"a\":2,\"b\":1}")
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
