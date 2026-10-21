//
//  StoreTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Petition stores: in memory, and as private files, plain or sealed with AES-GCM so the
//        disk never holds a patient's words in the clear.
//

import Foundation
import Testing
@testable import Bless

@Suite("Stores")
struct StoreTests {
    func temporary() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bless-store-\(UUID())/petitions")
    }

    func submitted(into store: any PetitionStore) async throws -> Petition {
        let gate = Fixture.gate(store: store)
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [Fixture.reviewer(1).party])
        try await gate.decide(petition.id, .amend(content: "Take it with food."), as: Fixture.reviewer(1))
        return try await gate.petition(petition.id)
    }

    @Test("the memory store saves, loads and lists")
    func memory() async throws {
        let store = MemoryPetitionStore()
        let petition = try await submitted(into: store)
        #expect(try store.load(petition.id) == petition)
        #expect(try store.all() == [petition])
        #expect(try store.load("nope") == nil)
    }

    @Test("the file store writes one 0600 JSON file per petition in a 0700 directory, and reads it back")
    func file() async throws {
        let dir = temporary()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = try FilePetitionStore(directory: dir)
        let petition = try await submitted(into: store)
        let file = dir.appendingPathComponent("\(petition.id).json")
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int) == 0o700)
        #expect(try FilePetitionStore(directory: dir).load(petition.id) == petition)
        #expect(try store.all().map(\.id) == [petition.id])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["\(petition.id).json"])
    }

    @Test("sealed with AES-GCM, the file holds no plaintext and reads back with the key")
    func sealed() async throws {
        let dir = temporary()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let key = AESGCMCipher.generateKey()
        let store = try FilePetitionStore(directory: dir, cipher: try AESGCMCipher(keyData: key))
        let petition = try await submitted(into: store)
        let bytes = try Data(contentsOf: dir.appendingPathComponent("\(petition.id).sealed"))
        #expect(bytes.range(of: Data("amoxicillin".utf8)) == nil)
        #expect(bytes.range(of: Data("Take it".utf8)) == nil)
        #expect(try store.load(petition.id) == petition)
    }

    @Test("the wrong key does not open a sealed petition")
    func wrongKey() async throws {
        let dir = temporary()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let petition = try await submitted(into: try FilePetitionStore(directory: dir, cipher: try AESGCMCipher(keyData: AESGCMCipher.generateKey())))
        let wrong = try FilePetitionStore(directory: dir, cipher: try AESGCMCipher(keyData: AESGCMCipher.generateKey()))
        #expect(throws: BlessError.self) { try wrong.load(petition.id) }
        #expect(throws: BlessError.self) { try AESGCMCipher(keyData: Data(count: 16)) }
    }

    @Test("an id that could name another path is refused")
    func unsafeID() throws {
        let dir = temporary()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = try FilePetitionStore(directory: dir)
        #expect(throws: BlessError.self) { try store.load("../escape") }
        #expect(throws: BlessError.self) { try store.load("") }
    }
}
