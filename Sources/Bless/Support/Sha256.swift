//
//  Sha256.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A SHA-256 digest as a value: what a petition's text is pinned to, what a verdict
//        endorses, and what links one ledger event to the next. `Sha256.of("text")` is the
//        digest of the string's UTF-8 bytes exactly as given (no normalization), so
//        `printf %s text | shasum -a 256` reproduces it. JSON carries it as lowercase hex.
//  PIN:  Named Sha256, not Digest: CryptoKit and swift-crypto both declare a `Digest` protocol,
//        and a Sewn file importing both would otherwise have to qualify every use.
//

import CryptoKit
import Foundation

public struct Sha256: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The 32 bytes of the digest.
    public let bytes: Data

    init(unchecked bytes: Data) {
        self.bytes = bytes
    }

    /// A digest from its 32 raw bytes, or nil for any other length.
    public init?(bytes: Data) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    /// A digest from 64 hex digits (either case), or nil.
    public init?(hex: String) {
        guard hex.utf8.count == 64 else { return nil }
        var out = Data(capacity: 32)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        self.bytes = out
    }

    /// The digest of a string's UTF-8 bytes, exactly as given.
    public static func of(_ text: String) -> Sha256 {
        of(Data(text.utf8))
    }

    /// The digest of some bytes.
    public static func of(_ data: Data) -> Sha256 {
        Sha256(unchecked: Data(SHA256.hash(data: data)))
    }

    /// Thirty-two zero bytes: the `previous` of a ledger's first event.
    public static let zero = Sha256(unchecked: Data(count: 32))

    /// Lowercase hex, 64 digits.
    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The first twelve hex digits, for a person to compare at a glance.
    public var prefix: String {
        String(hex.prefix(12))
    }

    public var description: String { hex }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Sha256(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a SHA-256 in hex: \(text.prefix(80))")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
