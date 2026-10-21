//
//  PetitionStore.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where petitions are kept between their submission and their release: save one (a new
//        petition or its latest state), load one, list them. In memory here; FilePetitionStore
//        keeps one private file per petition, optionally sealed with AES-GCM.
//  PIN:  Synchronous on purpose, as LedgerStore: the Gate's transitions must not suspend.
//

import Foundation
import Synchronization

public protocol PetitionStore: Sendable {
    func save(_ petition: Petition) throws
    func load(_ id: Petition.ID) throws -> Petition?
    /// Every petition, oldest first.
    func all() throws -> [Petition]
}

public final class MemoryPetitionStore: PetitionStore {
    private let petitions = Mutex<[Petition.ID: Petition]>([:])

    public init() {}

    public func save(_ petition: Petition) throws {
        petitions.withLock { $0[petition.id] = petition }
    }

    public func load(_ id: Petition.ID) throws -> Petition? {
        petitions.withLock { $0[id] }
    }

    public func all() throws -> [Petition] {
        petitions.withLock { Array($0.values) }.sorted(by: Petition.oldestFirst)
    }
}

extension Petition {
    static func oldestFirst(_ a: Petition, _ b: Petition) -> Bool {
        a.submitted == b.submitted ? a.id.rawValue < b.id.rawValue : a.submitted < b.submitted
    }
}
