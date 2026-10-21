//
//  Canonical.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The exact bytes a seal signs and a ledger hash covers. Each record starts with a
//        domain tag that names its layout and version (`bless/verdict/1`, `bless/event/1`), then
//        its fields in a fixed order, each written one way:
//          string    UInt32 big-endian byte count, then the UTF-8 bytes as given
//          int64     8 bytes big-endian (timestamps are whole milliseconds since 1970)
//          sha256    the 32 raw bytes
//          optional  0x00 for absent, or 0x01 then the value
//        Enum cases are written as their raw-value strings, so reordering a Swift enum never
//        changes a signature. Docs/INTEGRATION.md shows the layout field by field, and the site
//        recomputes it in the browser (js/hash.js).
//  PIN:  Not JSON. JSONEncoder's bytes for numbers, dates and escapes have changed across
//        Foundation rewrites, and a signature must outlive them. Changing a layout means a new
//        domain tag (`/2`), never an edit to `/1`: every stored signature depends on it.
//        Every Bless timestamp passes through `stamp` first, so a JSON round trip (which keeps
//        milliseconds) gives back the exact Date that was signed.
//

import Foundation

enum Canonical {
    /// Appends fields in the canonical forms.
    struct Writer {
        private(set) var data = Data()

        mutating func tag(_ tag: String) {
            string(tag)
        }

        mutating func string(_ value: String) {
            let utf8 = Data(value.utf8)
            uint32(UInt32(utf8.count))
            data.append(utf8)
        }

        mutating func optional(_ value: String?) {
            guard let value else { return data.append(0) }
            data.append(1)
            string(value)
        }

        mutating func int64(_ value: Int64) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }

        mutating func sha256(_ value: Sha256) {
            data.append(value.bytes)
        }

        mutating func optional(_ value: Sha256?) {
            guard let value else { return data.append(0) }
            data.append(1)
            sha256(value)
        }

        private mutating func uint32(_ value: UInt32) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
    }

    static let verdictTag = "bless/verdict/1"
    static let eventTag = "bless/event/1"

    /// Whole milliseconds since 1970. Rounds, so a stamped Date read back from JSON gives back
    /// the same count.
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// A date from whole milliseconds since 1970.
    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// The date truncated to whole milliseconds: what Bless stores, signs and chains.
    static func stamp(_ date: Date) -> Date {
        Self.date(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded(.down)))
    }

    /// What a reviewer's seal signs: everything in the verdict but the signature.
    static func verdict(_ verdict: Verdict) -> Data {
        var writer = Writer()
        writer.tag(verdictTag)
        writer.string(verdict.petitionID.rawValue)
        writer.string(verdict.reviewer.rawValue)
        writer.string(verdict.ruling.kind.rawValue)
        switch verdict.ruling {
        case .bless: break
        case .amend(let content): writer.string(content)
        case .withhold(let reason): writer.string(reason)
        }
        writer.sha256(verdict.digest)
        writer.optional(verdict.note)
        writer.int64(milliseconds(verdict.issued))
        return writer.data
    }

    /// What a ledger event's hash covers: everything in the event but the hash itself,
    /// `previous` last, so each hash commits to the whole chain before it.
    static func event(seq: Int, at: Date, kind: LedgerEvent.Kind, petitionID: Petition.ID,
                      actor: Party.ID?, digest: Sha256?, code: String?, previous: Sha256) -> Data {
        var writer = Writer()
        writer.tag(eventTag)
        writer.int64(Int64(seq))
        writer.int64(milliseconds(at))
        writer.string(kind.rawValue)
        writer.string(petitionID.rawValue)
        writer.optional(actor?.rawValue)
        writer.optional(digest)
        writer.optional(code)
        writer.sha256(previous)
        return writer.data
    }
}
