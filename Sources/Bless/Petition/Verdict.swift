//
//  Verdict.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: One reviewer's ruling on one petition, pinned to the exact text they read (`digest`)
//        and, when sealed, signed with their key over its canonical bytes. `endorsed` is the
//        text the verdict puts its name to: the digest itself for a blessing, the amendment's
//        digest for an amendment, nothing for a withholding.
//  PIN:  `issued` is stamped to whole milliseconds on creation, so the signed bytes survive a
//        JSON round trip.
//

import Foundation

public struct Verdict: Codable, Sendable, Equatable {
    public let petitionID: Petition.ID
    public let reviewer: Party.ID
    public let ruling: Ruling
    /// The SHA-256 of the text the reviewer read.
    public let digest: Sha256
    public let note: String?
    public let issued: Date
    /// The Ed25519 signature over `canonicalBytes`, when sealed.
    public internal(set) var signature: Data?

    public init(petitionID: Petition.ID, reviewer: Party.ID, ruling: Ruling, digest: Sha256, note: String? = nil,
                issued: Date = Date(), signature: Data? = nil) {
        self.petitionID = petitionID
        self.reviewer = reviewer
        self.ruling = ruling
        self.digest = digest
        self.note = note
        self.issued = Canonical.stamp(issued)
        self.signature = signature
    }

    /// The digest of the text this verdict endorses, or nil for a withholding.
    public var endorsed: Sha256? {
        switch ruling {
        case .bless: digest
        case .amend(let content): .of(content)
        case .withhold: nil
        }
    }

    /// The bytes a seal signs: everything but the signature (Canonical, `bless/verdict/1`).
    public var canonicalBytes: Data { Canonical.verdict(self) }
}
