//
//  Party.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A person in a conversation: the recipient of a reply, or a reviewer of it. A reviewer
//        carries the public half of their signing key, which the Gate checks every verdict's
//        seal against. The role is not stored here: the same doctor reviews one petition and may
//        receive another, so each Petition names its recipient and its reviewers.
//

import Foundation

public struct Party: Codable, Sendable, Hashable, Identifiable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public var description: String { rawValue }
    }

    public let id: ID
    public var displayName: String
    /// The raw 32-byte Curve25519 (Ed25519) public key a reviewer's seals verify against.
    public var verifyingKey: Data?

    public init(id: ID, displayName: String, verifyingKey: Data? = nil) {
        self.id = id
        self.displayName = displayName
        self.verifyingKey = verifyingKey
    }

    /// The first 16 hex digits of the SHA-256 of the verifying key, for a person to read aloud.
    public var fingerprint: String? {
        verifyingKey.map { String(Sha256.of($0).hex.prefix(16)) }
    }
}
