//
//  FilePetitionStore.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Petitions kept as one private file each in a private directory: `<id>.json`, or
//        `<id>.sealed` when a StoreCipher encrypts them. Writes are atomic, so a crash leaves
//        either the old state or the new, never half of one.
//  PIN:  Ids must be letters, digits and hyphens (what Petition.ID makes), so no id can name a
//        path outside the directory.
//

import Foundation
import Synchronization

public final class FilePetitionStore: PetitionStore {
    public let directory: URL
    private let cipher: (any StoreCipher)?
    private let lock = Mutex<Void>(())

    public init(directory: URL, cipher: (any StoreCipher)? = nil) throws {
        self.directory = directory
        self.cipher = cipher
        try PrivateFile.createDirectory(directory)
    }

    private var suffix: String { cipher == nil ? "json" : "sealed" }

    private func url(_ id: Petition.ID) throws -> URL {
        let safe = !id.rawValue.isEmpty && id.rawValue.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }
        guard safe else { throw BlessError.store("a petition id may hold only letters, digits and hyphens") }
        return directory.appendingPathComponent("\(id.rawValue).\(suffix)")
    }

    public func save(_ petition: Petition) throws {
        var data = try JSONCoding.encoder().encode(petition)
        if let cipher { data = try cipher.seal(data) }
        let target = try url(petition.id)
        try lock.withLock { _ in try PrivateFile.writeAtomically(data, to: target) }
    }

    public func load(_ id: Petition.ID) throws -> Petition? {
        let source = try url(id)
        return try lock.withLock { _ in
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            return try decode(try PrivateFile.read(source))
        }
    }

    public func all() throws -> [Petition] {
        try lock.withLock { _ in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return try names.filter { $0.hasSuffix(".\(suffix)") && !$0.hasPrefix(".") }.map {
                try decode(try PrivateFile.read(directory.appendingPathComponent($0)))
            }
        }.sorted(by: Petition.oldestFirst)
    }

    private func decode(_ data: Data) throws -> Petition {
        let plain = try cipher?.open(data) ?? data
        do {
            return try JSONCoding.decoder().decode(Petition.self, from: plain)
        } catch {
            throw BlessError.store("a petition file did not decode")
        }
    }
}
