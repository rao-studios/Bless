//
//  PetitionTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The rules a petition moves by, as pure functions, with no Gate: withhold wins, blessings
//        bind to the text, no stale verdicts, one blessing per reviewer per text, late verdicts
//        are refused, a lapse is the policy's.
//

import Foundation
import Testing
@testable import Bless

@Suite("Petition rules")
struct PetitionTests {
    static let t0 = Date(timeIntervalSince1970: 1_760_961_600)
    let a = Fixture.reviewer(1)
    let b = Fixture.reviewer(2)

    func petition(quorum: Int = 1, reviewers: [ReviewerIdentity]? = nil, policy: Policy? = nil,
                  deadline: Date? = nil) -> Petition {
        let draft = Fixture.draft()
        let policy = policy ?? Policy(quorum: quorum)
        return Petition(id: "p-1", conversationID: draft.conversationID, context: policy.trimmed(draft.context),
                        proposed: draft.proposed, provenance: draft.provenance, recipient: Fixture.patient,
                        reviewers: (reviewers ?? [a, b]).map(\.party), policy: policy, submitted: Self.t0, deadline: deadline)
    }

    func verdict(_ reviewer: ReviewerIdentity, _ ruling: Ruling, on petition: Petition) -> Verdict {
        try! reviewer.verdict(ruling, on: petition, issued: Self.t0)
    }

    @Test("quorum 1: the first blessing blesses")
    func quorumOne() throws {
        let p = petition()
        let next = try p.applying(verdict(a, .bless, on: p), at: Self.t0)
        #expect(next.standing == .blessed)
        #expect(next.blessings.map(\.reviewer) == [a.party.id])
        #expect(next.decided == Self.t0)
    }

    @Test("withhold wins over a blessing short of quorum")
    func withholdWins() throws {
        let p = petition(quorum: 2)
        let one = try p.applying(verdict(a, .bless, on: p), at: Self.t0)
        #expect(one.standing == .pending)
        let two = try one.applying(verdict(b, .withhold(reason: "needs a call"), on: one), at: Self.t0)
        #expect(two.standing == .withheld)
        #expect(two.withheldReason == "needs a call")
    }

    @Test("blessings bind to the text: an amendment starts the count again with the amender")
    func amendmentResets() throws {
        let p = petition(quorum: 2)
        let blessed = try p.applying(verdict(a, .bless, on: p), at: Self.t0)
        let amended = try blessed.applying(verdict(b, .amend(content: "Take it with food, twice a day, for 7 days."), on: blessed), at: Self.t0)
        #expect(amended.standing == .pending)
        #expect(amended.blessings.map(\.reviewer) == [b.party.id])
        #expect(amended.verdicts.count == 2)
        let done = try amended.applying(verdict(a, .bless, on: amended), at: Self.t0)
        #expect(done.standing == .blessed)
        #expect(Set(done.blessings.map(\.reviewer)) == [a.party.id, b.party.id])
        #expect(done.message.content == "Take it with food, twice a day, for 7 days.")
    }

    @Test("a stale verdict, given on a text that has since changed, is refused")
    func stale() throws {
        let p = petition(quorum: 2)
        let seenByA = verdict(a, .bless, on: p)
        let amended = try p.applying(verdict(b, .amend(content: "Something else."), on: p), at: Self.t0)
        #expect(throws: BlessError.staleVerdict(expected: amended.digest, saw: p.digest)) {
            try amended.applying(seenByA, at: Self.t0)
        }
    }

    @Test("one blessing per reviewer per text; a withholding is always heard")
    func duplicates() throws {
        let p = petition(quorum: 2)
        let once = try p.applying(verdict(a, .bless, on: p), at: Self.t0)
        #expect(throws: BlessError.duplicateVerdict(a.party.id)) { try once.applying(verdict(a, .bless, on: once), at: Self.t0) }
        #expect(throws: BlessError.duplicateVerdict(a.party.id)) {
            try once.applying(verdict(a, .amend(content: once.message.content), on: once), at: Self.t0)
        }
        let withheld = try once.applying(verdict(a, .withhold(reason: "second thoughts"), on: once), at: Self.t0)
        #expect(withheld.standing == .withheld)
    }

    @Test("a decided petition refuses every later verdict")
    func late() throws {
        let p = petition()
        let blessed = try p.applying(verdict(a, .bless, on: p), at: Self.t0)
        #expect(throws: BlessError.alreadyDecided("p-1", .blessed)) {
            try blessed.applying(verdict(b, .withhold(reason: "late"), on: blessed), at: Self.t0)
        }
    }

    @Test("a stranger's verdict is refused")
    func stranger() {
        let p = petition()
        let c = Fixture.reviewer(3)
        #expect(throws: BlessError.notAReviewer(c.party.id)) { try p.applying(verdict(c, .bless, on: p), at: Self.t0) }
    }

    @Test("an amendment is refused when the policy forbids it, and an empty one always")
    func amendmentRules() {
        let strict = petition(policy: Policy(allowsAmendment: false))
        #expect(throws: BlessError.amendmentNotAllowed) {
            try strict.applying(verdict(a, .amend(content: "Changed."), on: strict), at: Self.t0)
        }
        let p = petition()
        #expect(throws: BlessError.self) { try p.applying(verdict(a, .amend(content: ""), on: p), at: Self.t0) }
    }

    @Test("message, digest and amended are derived; the proposed text never changes")
    func derived() throws {
        let p = petition()
        #expect(p.message == p.proposed)
        #expect(!p.amended)
        let next = try p.applying(verdict(a, .amend(content: "Take it with water."), on: p), at: Self.t0)
        #expect(next.proposed == p.proposed)
        #expect(next.message.content == "Take it with water.")
        #expect(next.digest == .of("Take it with water."))
        #expect(next.amended)
    }

    @Test("the kept context drops system messages and keeps the latest turns the window allows")
    func context() {
        let messages = Fixture.draft().context
        #expect(Policy().trimmed(messages).map(\.role) == [.user, .assistant, .user])
        #expect(Policy(contextWindow: 1).trimmed(messages) == [.user("Yes, the first.")])
        #expect(Policy(contextWindow: 0).trimmed(messages).isEmpty)
    }

    @Test("a lapse: hold never lapses; withhold and fallback expire it at the deadline, not before")
    func lapses() {
        let deadline = Self.t0.addingTimeInterval(60)
        let hold = petition(policy: Policy(deadline: .seconds(60)), deadline: deadline)
        #expect(hold.lapsed(at: deadline.addingTimeInterval(1)) == nil)
        let withhold = petition(policy: Policy(deadline: .seconds(60), onLapse: .withhold), deadline: deadline)
        #expect(withhold.lapsed(at: deadline.addingTimeInterval(-1)) == nil)
        #expect(withhold.lapsed(at: deadline)?.standing == .expired)
        #expect(withhold.lapsed(at: deadline)?.fallback == nil)
        let fallback = petition(policy: Policy(deadline: .seconds(60), onLapse: .releaseFallback("Your care team will reply soon.")),
                                deadline: deadline)
        #expect(fallback.lapsed(at: deadline)?.fallback == "Your care team will reply soon.")
    }

    @Test("a verdict after a lapsing deadline is refused as expired")
    func pastDeadline() {
        let deadline = Self.t0.addingTimeInterval(60)
        let p = petition(policy: Policy(deadline: .seconds(60), onLapse: .withhold), deadline: deadline)
        #expect(throws: BlessError.expired("p-1")) { try p.applying(verdict(a, .bless, on: p), at: deadline) }
    }

    @Test("a policy is validated against its reviewers")
    func validation() {
        let keyless = Party(id: "dr-k", displayName: "No key")
        #expect(throws: BlessError.self) { try Policy().validate(reviewers: []) }
        #expect(throws: BlessError.self) { try Policy(quorum: 3).validate(reviewers: [a.party, b.party]) }
        #expect(throws: BlessError.self) { try Policy().validate(reviewers: [a.party, a.party]) }
        #expect(throws: BlessError.sealRequired("dr-k")) { try Policy().validate(reviewers: [keyless]) }
        #expect(throws: Never.self) { try Policy(requiresSeal: false).validate(reviewers: [keyless]) }
        #expect(throws: BlessError.self) { try Policy(deadline: .zero).validate(reviewers: [a.party]) }
        #expect(throws: BlessError.self) { try Policy(onLapse: .releaseFallback("")).validate(reviewers: [a.party]) }
    }

    @Test("a policy round-trips through JSON, deadline in milliseconds")
    func policyJSON() throws {
        let policy = Policy(quorum: 2, deadline: .milliseconds(90_500), onLapse: .releaseFallback("Soon."), allowsAmendment: false,
                            contextWindow: 4, requiresSeal: true)
        let json = try JSONCoding.encoder().encode(policy)
        #expect(String(decoding: json, as: UTF8.self).contains("\"deadlineMilliseconds\":90500"))
        #expect(try JSONCoding.decoder().decode(Policy.self, from: json) == policy)
        let plain = try JSONCoding.decoder().decode(Policy.self, from: try JSONCoding.encoder().encode(Policy()))
        #expect(plain == Policy())
    }

    @Test("a ruling is written as its kind and its text")
    func rulingJSON() throws {
        let json = try JSONCoding.encoder().encode([Ruling.bless, .amend(content: "x"), .withhold(reason: "y")])
        #expect(String(decoding: json, as: UTF8.self) == "[{\"kind\":\"bless\"},{\"content\":\"x\",\"kind\":\"amend\"},{\"kind\":\"withhold\",\"reason\":\"y\"}]")
        #expect(try JSONCoding.decoder().decode([Ruling].self, from: json) == [.bless, .amend(content: "x"), .withhold(reason: "y")])
    }
}
