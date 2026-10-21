//
//  ReviewerIdentity.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A reviewer and their private signing key, on the reviewer's own device: it turns a
//        ruling on a petition into a sealed Verdict, which the Gate verifies against the public
//        key the reviewer's Party carries. The Gate never needs the private key.
//  PIN:  The key is held as its 32 raw bytes (Curve25519.Signing's rawRepresentation), so the
//        identity is plainly Sendable and the host can keep those bytes in its keychain.
//        CryptoKit's Ed25519 signatures are randomized: two seals over the same verdict differ,
//        and both verify.
//

import CryptoKit
import Foundation

public struct ReviewerIdentity: Sendable {
    /// The reviewer as petitions name them, with the verifying key.
    public let party: Party
    /// The raw 32-byte private key. Keep it where the host keeps secrets.
    public let privateKey: Data

    /// A reviewer with a fresh key.
    public init(id: Party.ID, displayName: String) {
        let key = Curve25519.Signing.PrivateKey()
        self.privateKey = key.rawRepresentation
        self.party = Party(id: id, displayName: displayName, verifyingKey: key.publicKey.rawRepresentation)
    }

    /// A reviewer whose key was kept from before.
    public init(id: Party.ID, displayName: String, privateKey raw: Data) throws {
        let key: Curve25519.Signing.PrivateKey
        do {
            key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } catch {
            throw BlessError.invalidPolicy("a reviewer's private key is 32 raw bytes")
        }
        self.privateKey = key.rawRepresentation
        self.party = Party(id: id, displayName: displayName, verifyingKey: key.publicKey.rawRepresentation)
    }

    /// The raw 32-byte public key.
    public var verifyingKey: Data { party.verifyingKey ?? Data() }

    /// The verifying key's fingerprint.
    public var fingerprint: String { party.fingerprint ?? "" }

    /// The ruling, sealed: a Verdict on the petition's current text, signed with this key.
    public func verdict(_ ruling: Ruling, on petition: Petition, note: String? = nil, issued: Date = Date()) throws -> Verdict {
        let unsigned = Verdict(petitionID: petition.id, reviewer: party.id, ruling: ruling,
                               digest: petition.digest, note: note, issued: issued)
        return try Seal.sign(unsigned, privateKey: privateKey)
    }
}
