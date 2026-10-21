//
//  Petition.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A reply held for review: the proposed text, the conversation the policy lets reviewers
//        see, who it is for, who may rule on it, and every verdict so far. What the recipient
//        would get (`message`), its digest and its blessings are derived from those, never
//        stored beside them. The rules that move a petition are pure functions here, so they are
//        tested without a Gate:
//          withhold wins          any withholding before the petition is blessed ends it
//          blessings bind to text only verdicts endorsing the current digest count; an amendment
//                                 makes a new digest, so the count starts again with the amender
//          no stale verdicts      a verdict on a text that is no longer current is refused
//          one blessing per text  a reviewer blesses a text once; a withholding is always heard
//          late is refused        a decided, lapsed or withdrawn petition accepts nothing
//          a lapse is the policy's at the deadline the policy, not a reviewer, decides
//

import Foundation

public struct Petition: Codable, Sendable, Equatable, Identifiable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        /// A fresh random id.
        public init() { self.rawValue = UUID().uuidString.lowercased() }
        public var description: String { rawValue }
    }

    /// Where a petition stands. Every case but `pending` is final.
    public enum Standing: String, Codable, Sendable, CaseIterable {
        case pending, blessed, withheld, expired, withdrawn
    }

    public let id: ID
    public let conversationID: String
    /// The conversation as the policy lets reviewers see it (no system messages).
    public let context: [ChatMessage]
    /// The model's reply, as proposed. It never changes; amendments live in `verdicts`.
    public let proposed: ChatMessage
    public let provenance: Provenance
    public let recipient: Party
    public let reviewers: [Party]
    public let policy: Policy
    public let submitted: Date
    public let deadline: Date?
    public internal(set) var verdicts: [Verdict]
    public internal(set) var standing: Standing
    public internal(set) var decided: Date?
    /// When the Gate first handed out this petition's Release.
    public internal(set) var released: Date?

    init(id: ID, conversationID: String, context: [ChatMessage], proposed: ChatMessage, provenance: Provenance,
         recipient: Party, reviewers: [Party], policy: Policy, submitted: Date, deadline: Date?) {
        self.id = id
        self.conversationID = conversationID
        self.context = context
        self.proposed = proposed
        self.provenance = provenance
        self.recipient = recipient
        self.reviewers = reviewers
        self.policy = policy
        self.submitted = submitted
        self.deadline = deadline
        self.verdicts = []
        self.standing = .pending
        self.decided = nil
        self.released = nil
    }

    // MARK: Derived

    /// What the recipient would get: the latest amendment, else the proposed text.
    public var message: ChatMessage {
        for verdict in verdicts.reversed() {
            if case .amend(let content) = verdict.ruling { return .assistant(content) }
        }
        return .assistant(proposed.content)
    }

    /// The SHA-256 of `message`.
    public var digest: Sha256 { .of(message.content) }

    /// Whether a reviewer changed the text.
    public var amended: Bool { message.content != proposed.content }

    /// The verdicts that endorse the current text, one per reviewer.
    public var blessings: [Verdict] {
        let current = digest
        var seen: Set<Party.ID> = []
        return verdicts.filter { $0.endorsed == current && seen.insert($0.reviewer).inserted }
    }

    /// The withholding that ended the petition, if one did.
    public var withholding: Verdict? {
        verdicts.first { $0.ruling.kind == .withhold }
    }

    /// The reviewer's withholding reason, when a reviewer withheld it.
    public var withheldReason: String? {
        if case .withhold(let reason)? = withholding?.ruling { return reason }
        return nil
    }

    public var isTerminal: Bool { standing != .pending }

    public func reviewer(_ id: Party.ID) -> Party? {
        reviewers.first { $0.id == id }
    }

    // MARK: The rules

    /// The petition with this verdict applied, or the rule it breaks. `now` decides lateness.
    public func applying(_ verdict: Verdict, at now: Date) throws -> Petition {
        guard standing == .pending else { throw BlessError.alreadyDecided(id, standing) }
        guard verdict.petitionID == id else { throw BlessError.unknownPetition(verdict.petitionID) }
        guard reviewer(verdict.reviewer) != nil else { throw BlessError.notAReviewer(verdict.reviewer) }
        if let deadline, now >= deadline, policy.onLapse != .hold { throw BlessError.expired(id) }
        let current = digest
        guard verdict.digest == current else { throw BlessError.staleVerdict(expected: current, saw: verdict.digest) }

        var next = self
        switch verdict.ruling {
        case .withhold:
            next.verdicts.append(verdict)
            next.standing = .withheld
            next.decided = Canonical.stamp(now)
            return next
        case .amend(let content) where Sha256.of(content) != current:
            guard policy.allowsAmendment else { throw BlessError.amendmentNotAllowed }
            guard !content.isEmpty else { throw BlessError.invalidDraft("an amendment cannot be empty") }
            next.verdicts.append(verdict)
        case .bless, .amend:
            // An amendment that leaves the text as it is reads as a blessing of it.
            guard !blessings.contains(where: { $0.reviewer == verdict.reviewer }) else {
                throw BlessError.duplicateVerdict(verdict.reviewer)
            }
            next.verdicts.append(verdict)
        }
        if next.blessings.count >= policy.quorum {
            next.standing = .blessed
            next.decided = Canonical.stamp(now)
        }
        return next
    }

    /// The petition after its deadline, when the deadline has passed and the policy lets it
    /// lapse; nil when it is not due, already final, or the policy holds.
    public func lapsed(at now: Date) -> Petition? {
        guard standing == .pending, let deadline, now >= deadline else { return nil }
        if case .hold = policy.onLapse { return nil }
        var next = self
        next.standing = .expired
        next.decided = Canonical.stamp(now)
        return next
    }

    /// The fixed text a lapsed petition releases, when its policy names one.
    public var fallback: String? {
        if case .releaseFallback(let text) = policy.onLapse, standing == .expired { return text }
        return nil
    }
}
