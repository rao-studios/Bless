//
//  LedgerEvent.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: One line of the audit log: what happened (kind), to which petition, by whom, to which
//        text (digest), with which coded outcome, and when. Each event's hash covers its fields
//        and the previous event's hash, so changing, dropping or reordering any event breaks
//        every hash after it.
//  PIN:  No content and no free text, ever: a text appears only as its SHA-256, a ruling or an
//        error only as its code name. A withholding reason like a test result would otherwise
//        land in a log every auditor reads. PackageLayeringTests checks that Ledger/ never
//        touches a message's content.
//

import Foundation

public struct LedgerEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A draft was held as a petition.
        case submitted
        /// A reviewer opened it.
        case viewed
        /// A reviewer gave a verdict (code: the ruling's kind).
        case decided
        /// The quorum was met.
        case blessed
        /// A reviewer withheld it.
        case withheld
        /// The deadline passed (code: the policy's lapse).
        case expired
        /// The host withdrew it before a decision.
        case withdrawn
        /// The Gate first handed out its Release (code: the release's basis).
        case released
        /// The host delivered the Release.
        case dispatched
        /// Delivering the Release failed (code: the error's code).
        case failed
    }

    public let seq: Int
    public let at: Date
    public let kind: Kind
    public let petitionID: Petition.ID
    public let actor: Party.ID?
    public let digest: Sha256?
    /// A ruling kind, a lapse, a release basis or an error code: a name from Bless's own
    /// vocabulary, never free text.
    public let code: String?
    public let previous: Sha256
    public let hash: Sha256

    init(seq: Int, at: Date, kind: Kind, petitionID: Petition.ID, actor: Party.ID?, digest: Sha256?, code: String?,
         previous: Sha256) {
        self.seq = seq
        self.at = Canonical.stamp(at)
        self.kind = kind
        self.petitionID = petitionID
        self.actor = actor
        self.digest = digest
        self.code = code
        self.previous = previous
        self.hash = .of(Canonical.event(seq: seq, at: self.at, kind: kind, petitionID: petitionID, actor: actor,
                                        digest: digest, code: code, previous: previous))
    }

    /// The bytes the hash covers (Canonical, `bless/event/1`).
    public var canonicalBytes: Data {
        Canonical.event(seq: seq, at: at, kind: kind, petitionID: petitionID, actor: actor, digest: digest, code: code,
                        previous: previous)
    }

    /// The hash these fields should have; differs from `hash` when the event was changed.
    public var recomputedHash: Sha256 { .of(canonicalBytes) }
}
