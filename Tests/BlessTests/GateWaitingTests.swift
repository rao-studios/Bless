//
//  GateWaitingTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Waiting at the Gate: `release(for:)` suspends until a decision, many callers get the
//        same release, a cancelled caller leaves the review alone, and deadlines lapse by sweep or
//        on their own, with no continuation left behind.
//

import Foundation
import Testing
@testable import Bless

@Suite("Gate waiting")
struct GateWaitingTests {
    let doctor = Fixture.reviewer(1)

    @Test("release suspends until a verdict lands")
    func suspends() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party])
        let waiting = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 1 })
        try await gate.decide(petition.id, .bless, as: doctor)
        let release = try await waiting.value
        #expect(release.basis == .blessed)
        #expect(await gate.waiterCount == 0)
    }

    @Test("two waiters get the same release, and it is logged once")
    func twoWaiters() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party])
        let first = Task { try await gate.release(for: petition.id) }
        let second = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 2 })
        try await gate.decide(petition.id, .bless, as: doctor)
        let (a, b) = (try await first.value, try await second.value)
        #expect(a == b)
        #expect(try gate.ledger.events().filter { $0.kind == .released }.count == 1)
    }

    @Test("a cancelled waiter leaves the petition pending and writes nothing")
    func cancelled() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party])
        let waiting = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 1 })
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(await eventually { await gate.waiterCount == 0 })
        #expect(try await gate.petition(petition.id).standing == .pending)
        #expect(try gate.ledger.events().map(\.kind) == [.submitted])
    }

    @Test("a new waiter after a cancelled one still receives the release")
    func afterCancel() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party])
        let gone = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 1 })
        gone.cancel()
        _ = try? await gone.value
        let later = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 1 })
        try await gate.decide(petition.id, .amend(content: "Take it with food."), as: doctor)
        #expect(try await later.value.message.content == "Take it with food.")
    }

    @Test("onLapse hold keeps a petition pending past its deadline")
    func holdsPastDeadline() async throws {
        let clock = FakeClock()
        let gate = Fixture.gate(clock: clock)
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(60)))
        clock.advance(.seconds(120))
        #expect(try await gate.sweep().isEmpty)
        #expect(try await gate.petition(petition.id).standing == .pending)
    }

    @Test("onLapse withhold: a sweep past the deadline expires it, wakes its waiter, and release throws expired")
    func sweepExpires() async throws {
        let clock = FakeClock()
        let gate = Fixture.gate(clock: clock)
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(60), onLapse: .withhold))
        let waiting = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 1 })
        #expect(try await gate.sweep(now: clock.current.addingTimeInterval(30)).isEmpty)
        clock.advance(.seconds(61))
        #expect(try await gate.sweep().map(\.id) == [petition.id])
        await #expect(throws: BlessError.expired(petition.id)) { try await waiting.value }
        let expired = try gate.ledger.events().last
        #expect(expired?.kind == .expired && expired?.code == "withhold")
        #expect(await gate.waiterCount == 0)
    }

    @Test("a fallback lapse releases the policy's text with basis lapsed and no verdicts")
    func fallback() async throws {
        let clock = FakeClock()
        let gate = Fixture.gate(clock: clock)
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(60), onLapse: .releaseFallback("Your care team will reply soon.")))
        clock.advance(.seconds(60))
        let release = try await gate.release(for: petition.id)
        #expect(release.basis == .lapsed)
        #expect(release.message.content == "Your care team will reply soon.")
        #expect(release.verdicts.isEmpty)
        try release.verify(against: try await gate.petition(petition.id))
    }

    @Test("a verdict after the deadline is refused: the petition has lapsed")
    func lateVerdict() async throws {
        let clock = FakeClock()
        let gate = Fixture.gate(clock: clock)
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(60), onLapse: .withhold))
        clock.advance(.seconds(90))
        await #expect(throws: BlessError.alreadyDecided(petition.id, .expired)) { try await gate.decide(petition.id, .bless, as: doctor) }
    }

    @Test("a waiter with a deadline wakes itself when it passes, with no sweeper")
    func selfWake() async throws {
        let clock = FakeClock()
        let gate = Fixture.gate(clock: clock, sleeper: clock.advancing)
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(3600), onLapse: .withhold))
        await #expect(throws: BlessError.expired(petition.id)) { try await gate.release(for: petition.id) }
        #expect(try await gate.petition(petition.id).standing == .expired)
        #expect(await eventually { await gate.waiterCount == 0 })
    }

    @Test("a waiter with a deadline still takes a verdict that comes first")
    func verdictBeatsDeadline() async throws {
        let gate = Fixture.gate()
        let petition = try await gate.submit(Fixture.draft(), to: Fixture.patient, reviewers: [doctor.party],
                                             policy: Policy(deadline: .seconds(3600), onLapse: .withhold))
        let waiting = Task { try await gate.release(for: petition.id) }
        #expect(await eventually { await gate.waiterCount == 1 })
        try await gate.decide(petition.id, .bless, as: doctor)
        #expect(try await waiting.value.basis == .blessed)
        #expect(await eventually { await gate.waiterCount == 0 })
    }
}
