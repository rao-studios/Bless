//
//  Release.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The only thing a host may deliver to a recipient: the blessed (or amended) message, its
//        digest, and the sealed verdicts that allowed it; or, for a lapsed petition whose policy
//        names one, the policy's fixed fallback text with no verdicts. Only the Gate makes one.
//        `verify(against:)` re-checks it from scratch against the petition: the digest, every
//        seal, the quorum.
//

import Foundation

public struct Release: Codable, Sendable, Equatable {
    public enum Basis: String, Codable, Sendable, CaseIterable {
        /// Blessed as the model wrote it.
        case blessed
        /// Blessed after a reviewer changed it.
        case amended
        /// The deadline passed; the policy's fallback text, not the model's.
        case lapsed
    }

    public let petitionID: Petition.ID
    public let recipient: Party.ID
    public let message: ChatMessage
    public let digest: Sha256
    public let basis: Basis
    public let verdicts: [Verdict]
    public let released: Date

    /// The release a decided petition allows, or nil when it allows none.
    init?(petition: Petition, at released: Date) {
        switch petition.standing {
        case .blessed:
            self.message = petition.message
            self.basis = petition.amended ? .amended : .blessed
            self.verdicts = petition.blessings
        case .expired:
            guard let text = petition.fallback else { return nil }
            self.message = .assistant(text)
            self.basis = .lapsed
            self.verdicts = []
        case .pending, .withheld, .withdrawn:
            return nil
        }
        self.petitionID = petition.id
        self.recipient = petition.recipient.id
        self.digest = .of(message.content)
        self.released = released
    }

    /// Throws unless this release is exactly what the petition allows.
    public func verify(against petition: Petition) throws {
        guard petitionID == petition.id else { throw BlessError.invalidRelease("another petition's release") }
        guard recipient == petition.recipient.id else { throw BlessError.invalidRelease("addressed to someone else") }
        guard message.role == .assistant, digest == .of(message.content) else {
            throw BlessError.invalidRelease("the digest does not match the message")
        }
        switch basis {
        case .lapsed:
            guard petition.standing == .expired, let text = petition.fallback, message.content == text, verdicts.isEmpty else {
                throw BlessError.invalidRelease("a lapse releases only the policy's fallback")
            }
        case .blessed, .amended:
            guard petition.standing == .blessed, digest == petition.digest else {
                throw BlessError.invalidRelease("the petition did not bless this text")
            }
            guard (basis == .amended) == petition.amended else { throw BlessError.invalidRelease("the basis is wrong") }
            var reviewers: Set<Party.ID> = []
            for verdict in verdicts {
                guard verdict.petitionID == petition.id, verdict.endorsed == digest else {
                    throw BlessError.invalidRelease("a verdict endorses another text")
                }
                guard let reviewer = petition.reviewer(verdict.reviewer) else { throw BlessError.notAReviewer(verdict.reviewer) }
                if let key = reviewer.verifyingKey, verdict.signature != nil {
                    guard Seal.verify(verdict, verifyingKey: key) else { throw BlessError.badSeal(reviewer.id) }
                } else if petition.policy.requiresSeal {
                    throw BlessError.sealRequired(reviewer.id)
                }
                reviewers.insert(reviewer.id)
            }
            guard reviewers.count >= petition.policy.quorum else {
                throw BlessError.invalidRelease("\(reviewers.count) of \(petition.policy.quorum) blessings")
            }
        }
    }
}
