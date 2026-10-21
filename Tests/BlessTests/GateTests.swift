//
//  GateTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The Gate's transitions, one at a time: what submit checks and keeps, which verdicts it
//        accepts, what each release carries, and the ledger it writes along the way.
//

import Foundation
import Testing
@testable import Bless

@Suite("Gate")
struct GateTests {
    let doctor = Fixture.reviewer(1)
    let patient = Fixture.patient

    @Test("submit refuses a draft that is not the assistant's, a bad quorum, a keyless reviewer, a self-review")
    func submitChecks() async throws {
        let gate = Fixture.gate()
        var draft = Fixture.draft()
        draft.proposed = .user("not a reply")
        await #expect(throws: BlessError.self) { try await gate.submit(draft, to: patient, reviewers: [doctor.party]) }
        await #expect(throws: BlessError.self) {
            try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party], policy: Policy(quorum: 2))
        }
        await #expect(throws: BlessError.sealRequired("dr-k")) {
            try await gate.submit(Fixture.draft(), to: patient, reviewers: [Party(id: "dr-k", displayName: "K")])
        }
        let selfReview = Party(id: patient.id, displayName: "Ada", verifyingKey: doctor.verifyingKey)
        await #expect(throws: BlessError.self) { try await gate.submit(Fixture.draft(), to: patient, reviewers: [selfReview]) }
        #expect(try await gate.petitions().isEmpty)
        #expect(try gate.ledger.events().isEmpty)
    }

    @Test("submit trims the context, stores the petition and writes `submitted` with the draft's digest")
    func submitKeeps() async throws {
        let clock = FakeClock()
        let gate = Fixture.gate(clock: clock)
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(600), contextWindow: 2))
        #expect(petition.id == "p-1")
        #expect(petition.context == [.assistant("Is this your first course?"), .user("Yes, the first.")])
        #expect(petition.deadline == clock.current.addingTimeInterval(600))
        #expect(try await gate.petition(petition.id) == petition)
        let events = try gate.ledger.events()
        #expect(events.map(\.kind) == [.submitted])
        #expect(events[0].digest == Fixture.draft().digest)
        #expect(events[0].actor == nil && events[0].code == nil)
    }

    @Test("decide refuses an unsealed or forged verdict under a sealing policy")
    func sealsChecked() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        await #expect(throws: BlessError.sealRequired(doctor.party.id)) { try await gate.decide(petition.id, .bless, by: doctor.party.id) }
        let forged = try Fixture.reviewer(9).verdict(.bless, on: petition)
        let impostor = Verdict(petitionID: petition.id, reviewer: doctor.party.id, ruling: .bless, digest: petition.digest,
                               issued: forged.issued, signature: forged.signature)
        await #expect(throws: BlessError.badSeal(doctor.party.id)) { try await gate.decide(impostor) }
        #expect(try await gate.petition(petition.id).standing == .pending)
    }

    @Test("an unsealed verdict is accepted when the policy does not require seals")
    func unsealedPolicy() async throws {
        let gate = Fixture.gate()
        let nurse = Party(id: "nurse-1", displayName: "Nurse")
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [nurse], policy: Policy(requiresSeal: false))
        let decided = try await gate.decide(petition.id, .bless, by: nurse.id)
        #expect(decided.standing == .blessed)
        let release = try await gate.release(for: petition.id)
        try release.verify(against: try await gate.petition(petition.id))
    }

    @Test("a blessing releases the model's text, basis blessed, with the sealed verdict")
    func blessedRelease() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        try await gate.decide(petition.id, .bless, as: doctor)
        let release = try await gate.release(for: petition.id)
        #expect(release.message == .assistant("Take it with food, twice a day."))
        #expect(release.basis == .blessed)
        #expect(release.recipient == patient.id)
        #expect(release.verdicts.count == 1 && release.verdicts[0].signature != nil)
        try release.verify(against: try await gate.petition(petition.id))
        #expect(try await gate.release(for: petition.id) == release)
    }

    @Test("an amendment releases the amended text, basis amended, never the model's")
    func amendedRelease() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        try await gate.decide(petition.id, .amend(content: "Take it with food, twice a day, for all 7 days."), as: doctor)
        let release = try await gate.release(for: petition.id)
        #expect(release.message.content == "Take it with food, twice a day, for all 7 days.")
        #expect(release.basis == .amended)
        #expect(release.digest == .of("Take it with food, twice a day, for all 7 days."))
        try release.verify(against: try await gate.petition(petition.id))
    }

    @Test("a withholding releases nothing: release throws withheld with the reviewer's reason")
    func withheld() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        try await gate.decide(petition.id, .withhold(reason: "call the patient instead"), as: doctor)
        await #expect(throws: BlessError.withheld(petition.id, reason: "call the patient instead")) {
            try await gate.release(for: petition.id)
        }
        let kinds = try gate.ledger.events().map(\.kind)
        #expect(kinds == [.submitted, .decided, .withheld])
    }

    @Test("withdraw ends a pending petition, and only a pending one")
    func withdraw() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        #expect(try await gate.withdraw(petition.id).standing == .withdrawn)
        await #expect(throws: BlessError.withdrawn(petition.id)) { try await gate.release(for: petition.id) }
        await #expect(throws: BlessError.alreadyDecided(petition.id, .withdrawn)) { try await gate.withdraw(petition.id) }
        await #expect(throws: BlessError.self) { try await gate.decide(petition.id, .bless, as: doctor) }
    }

    @Test("pending lists by reviewer; markViewed writes `viewed` for reviewers only")
    func pendingAndViewed() async throws {
        let gate = Fixture.gate()
        let other = Fixture.reviewer(2)
        let mine = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        _ = try await gate.submit(Fixture.draft("Rest and fluids."), to: patient, reviewers: [other.party])
        #expect(try await gate.pending(for: doctor.party.id).map(\.id) == [mine.id])
        #expect(try await gate.pending().count == 2)
        try await gate.markViewed(mine.id, by: doctor.party.id)
        await #expect(throws: BlessError.notAReviewer(other.party.id)) { try await gate.markViewed(mine.id, by: other.party.id) }
        let viewed = try gate.ledger.events().last
        #expect(viewed?.kind == .viewed && viewed?.actor == doctor.party.id)
    }

    @Test("observe sees each transition")
    func observe() async throws {
        let gate = Fixture.gate()
        let stream = await gate.observe()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        try await gate.decide(petition.id, .bless, as: doctor)
        _ = try await gate.release(for: petition.id)
        var seen: [Petition.Standing] = []
        for await update in stream {
            seen.append(update.standing)
            if update.released != nil { break }
        }
        #expect(seen == [.pending, .blessed, .blessed])
    }

    @Test("dispatch verifies and delivers, writing `dispatched`; a failing dispatcher writes `failed` with a code")
    func dispatch() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        let dispatcher = RecordingDispatcher()
        await #expect(throws: BlessError.notBlessed(petition.id)) { try await gate.dispatch(petition.id, via: dispatcher) }
        try await gate.decide(petition.id, .bless, as: doctor)
        let release = try await gate.dispatch(petition.id, via: dispatcher)
        #expect(dispatcher.releases == [release])
        #expect(try gate.ledger.events().last?.kind == .dispatched)
        await #expect(throws: Delivery.self) { try await gate.dispatch(petition.id, via: RecordingDispatcher(failure: Delivery())) }
        let failed = try gate.ledger.events().last
        #expect(failed?.kind == .failed && failed?.code == "dispatcher")
    }

    @Test("a whole life reads submitted, viewed, decided, blessed, released, dispatched, and the chain verifies")
    func wholeLife() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party])
        try await gate.markViewed(petition.id, by: doctor.party.id)
        try await gate.decide(petition.id, .bless, as: doctor)
        _ = try await gate.dispatch(petition.id, via: RecordingDispatcher())
        let events = try gate.ledger.events()
        #expect(events.map(\.kind) == [.submitted, .viewed, .decided, .blessed, .released, .dispatched])
        #expect(events.map(\.seq) == Array(1...6))
        #expect(try gate.ledger.verify() == 6)
        #expect(events[4].code == "blessed")
    }

    @Test("quorum 2 through the Gate: one blessing waits, the second releases")
    func quorumTwo() async throws {
        let gate = Fixture.gate()
        let other = Fixture.reviewer(2)
        let petition = try await gate.submit(Fixture.draft(), to: patient, reviewers: [doctor.party, other.party],
                                             policy: Policy(quorum: 2))
        #expect(try await gate.decide(petition.id, .bless, as: doctor).standing == .pending)
        #expect(try await gate.decide(petition.id, .bless, as: other).standing == .blessed)
        let release = try await gate.release(for: petition.id)
        #expect(Set(release.verdicts.map(\.reviewer)) == [doctor.party.id, other.party.id])
        try release.verify(against: try await gate.petition(petition.id))
    }
}
