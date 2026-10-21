//
//  StoreCipher.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Encryption at rest for a petition store: `seal` before a petition is written, `open`
//        after it is read. AESGCMCipher is AES-256-GCM (CryptoKit), nonce and tag kept with the
//        ciphertext; a wrong key or a changed byte fails to open.
//  PIN:  Where the key comes from (Keychain, Secure Enclave, a KMS) and how it rotates are the
//        host's, and still open. The key is held as its raw bytes.
//

import CryptoKit
import Foundation

public protocol StoreCipher: Sendable {
    func seal(_ plaintext: Data) throws -> Data
    func open(_ ciphertext: Data) throws -> Data
}

public struct AESGCMCipher: StoreCipher {
    private let key: Data

    /// A cipher over a 32-byte key.
    public init(keyData: Data) throws {
        guard keyData.count == 32 else { throw BlessError.store("an AES-256 key is 32 bytes") }
        self.key = keyData
    }

    /// A cipher over a CryptoKit key.
    public init(key: SymmetricKey) throws {
        try self.init(keyData: key.withUnsafeBytes { Data($0) })
    }

    /// Thirty-two fresh random bytes, for a new key.
    public static func generateKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key)).combined else {
            throw BlessError.store("AES-GCM produced no output")
        }
        return combined
    }

    public func open(_ ciphertext: Data) throws -> Data {
        do {
            return try AES.GCM.open(try AES.GCM.SealedBox(combined: ciphertext), using: SymmetricKey(data: key))
        } catch {
            throw BlessError.store("a sealed petition did not open: the wrong key, or a changed file")
        }
    }
}
