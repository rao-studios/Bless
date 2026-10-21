//
//  BlessError.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Every way a Bless call can refuse. `code` is the case's name: the only part of an error
//        the ledger ever records, so an error's details (a reason, a store path) stay out of the
//        audit log.
//

import Foundation

public enum BlessError: Error, Equatable, CustomStringConvertible {
    /// No petition with this id is in the store.
    case unknownPetition(Petition.ID)
    /// The draft cannot be held: not the assistant's, or empty.
    case invalidDraft(String)
    /// The policy cannot be met by these reviewers.
    case invalidPolicy(String)
    /// The party is not one of the petition's reviewers.
    case notAReviewer(Party.ID)
    /// The petition has already been decided (or withdrawn); nothing more is accepted.
    case alreadyDecided(Petition.ID, Petition.Standing)
    /// The verdict was given on a text that is no longer the petition's.
    case staleVerdict(expected: Sha256, saw: Sha256)
    /// This reviewer has already blessed this text.
    case duplicateVerdict(Party.ID)
    /// The policy does not let reviewers change the text.
    case amendmentNotAllowed
    /// The policy needs a sealed verdict and this one is not, or the reviewer has no key.
    case sealRequired(Party.ID)
    /// The verdict's seal does not verify against the reviewer's key.
    case badSeal(Party.ID)
    /// A reviewer withheld the reply. The reason is the reviewer's, for the host's own records.
    case withheld(Petition.ID, reason: String)
    /// The deadline passed and the policy withholds a lapsed reply.
    case expired(Petition.ID)
    /// The petition was withdrawn before it was decided.
    case withdrawn(Petition.ID)
    /// There is nothing to release yet: the petition is not blessed.
    case notBlessed(Petition.ID)
    /// A release does not match its petition.
    case invalidRelease(String)
    /// The ledger's chain breaks at this event.
    case ledgerTampered(seq: Int)
    /// A store could not read or write.
    case store(String)

    /// The case's name, and nothing else: what the ledger may record.
    public var code: String {
        switch self {
        case .unknownPetition: "unknownPetition"
        case .invalidDraft: "invalidDraft"
        case .invalidPolicy: "invalidPolicy"
        case .notAReviewer: "notAReviewer"
        case .alreadyDecided: "alreadyDecided"
        case .staleVerdict: "staleVerdict"
        case .duplicateVerdict: "duplicateVerdict"
        case .amendmentNotAllowed: "amendmentNotAllowed"
        case .sealRequired: "sealRequired"
        case .badSeal: "badSeal"
        case .withheld: "withheld"
        case .expired: "expired"
        case .withdrawn: "withdrawn"
        case .notBlessed: "notBlessed"
        case .invalidRelease: "invalidRelease"
        case .ledgerTampered: "ledgerTampered"
        case .store: "store"
        }
    }

    public var description: String {
        switch self {
        case .unknownPetition(let id): "no petition \(id)"
        case .invalidDraft(let why): "the draft cannot be held: \(why)"
        case .invalidPolicy(let why): "the policy cannot be met: \(why)"
        case .notAReviewer(let id): "\(id) is not a reviewer of this petition"
        case .alreadyDecided(let id, let standing): "petition \(id) is already \(standing.rawValue)"
        case .staleVerdict(let expected, let saw): "the verdict was given on \(saw.prefix), but the petition's text is now \(expected.prefix)"
        case .duplicateVerdict(let id): "\(id) has already blessed this text"
        case .amendmentNotAllowed: "the policy does not allow amendments"
        case .sealRequired(let id): "the policy requires a sealed verdict from \(id)"
        case .badSeal(let id): "the seal on \(id)'s verdict does not verify"
        case .withheld(let id, _): "petition \(id) was withheld by its reviewer"
        case .expired(let id): "petition \(id) lapsed at its deadline and was withheld"
        case .withdrawn(let id): "petition \(id) was withdrawn"
        case .notBlessed(let id): "petition \(id) has nothing to release"
        case .invalidRelease(let why): "the release does not match its petition: \(why)"
        case .ledgerTampered(let seq): "the ledger's chain breaks at event \(seq)"
        case .store(let why): "store: \(why)"
        }
    }
}
