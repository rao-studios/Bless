//
//  Seal.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Signs a verdict with a reviewer's Ed25519 key and verifies one against the public key.
//        What is signed is the verdict's canonical bytes (`bless/verdict/1`): the petition, the
//        reviewer, the ruling and its text, the digest the reviewer read, the note, the time.
//  PIN:  Curve25519.Signing (Ed25519, RFC 8032) from CryptoKit; any RFC 8032 verifier accepts
//        these signatures (the site's figure verifies them with Web Crypto, INTEGRATION.md with
//        Python's `cryptography`).
//

import CryptoKit
import Foundation

public enum Seal {
    /// The verdict with its signature.
    public static func sign(_ verdict: Verdict, privateKey raw: Data) throws -> Verdict {
        let key: Curve25519.Signing.PrivateKey
        do {
            key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } catch {
            throw BlessError.invalidPolicy("a reviewer's private key is 32 raw bytes")
        }
        var signed = verdict
        signed.signature = try key.signature(for: verdict.canonicalBytes)
        return signed
    }

    /// Whether the verdict carries a signature that this public key made over its bytes.
    public static func verify(_ verdict: Verdict, verifyingKey raw: Data) -> Bool {
        guard let signature = verdict.signature,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: verdict.canonicalBytes)
    }
}
