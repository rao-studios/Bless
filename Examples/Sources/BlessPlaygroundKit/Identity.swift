//
//  Identity.swift
//  BlessPlaygroundKit
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The playground's reviewer: one Ed25519 identity made on first launch and kept in
//        ~/Library/Application Support/nyc.rao.bless.playground/reviewer.json (0600), so the
//        seals in a session's ledger verify against the same key next time. "Regenerate" makes a
//        new key; earlier seals then name a key that is gone, which is the point of showing it.
//  PIN:  A file, not the Keychain: this key signs only the playground's own demo ledger. A real
//        deployment keeps reviewers' keys on their devices (the Secure Enclave), never in a file.
//

import Bless
import Foundation

public struct ReviewerIdentityStore: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }

    public static func live() -> ReviewerIdentityStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReviewerIdentityStore(file: support.appendingPathComponent("nyc.rao.bless.playground/reviewer.json"))
    }

    private struct Stored: Codable {
        var id: String
        var displayName: String
        var privateKey: Data
        var created: Date
    }

    /// The kept identity, or a new one (saved) when there is none or it does not read.
    public func loadOrCreate(displayName: String = "Dr. Okafor") throws -> ReviewerIdentity {
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode(Stored.self, from: data),
           let identity = try? ReviewerIdentity(id: Party.ID(stored.id), displayName: stored.displayName, privateKey: stored.privateKey) {
            return identity
        }
        return try regenerate(displayName: displayName)
    }

    /// A fresh key under the same name, saved.
    public func regenerate(displayName: String) throws -> ReviewerIdentity {
        let identity = ReviewerIdentity(id: "dr-okafor", displayName: displayName)
        try save(identity)
        return identity
    }

    public func save(_ identity: ReviewerIdentity) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Stored(id: identity.party.id.rawValue, displayName: identity.party.displayName,
                                                   privateKey: identity.privateKey, created: Date()))
        let temporary = directory.appendingPathComponent(".reviewer.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// The same reviewer under a new display name, saved.
    public func rename(_ identity: ReviewerIdentity, to displayName: String) throws -> ReviewerIdentity {
        let renamed = try ReviewerIdentity(id: identity.party.id, displayName: displayName, privateKey: identity.privateKey)
        try save(renamed)
        return renamed
    }
}
