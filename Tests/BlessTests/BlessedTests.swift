//
//  BlessedTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The pattern end to end: Blessed around a model holds each reply, returns only the
//        blessed text, streams nothing before a verdict, and leaves a review alone when its
//        caller goes away.
//

import Foundation
import Synchronization
import Testing
@testable import Bless

@Suite("Blessed")
struct BlessedTests {
    let doctor = Fixture.reviewer(1)
    let request = ChatRequest(model: "test-model", messages: [.system("You draft replies for a clinician."), .user("How should I take it?")])

    func blessed(_ model: ScriptedProvider, gate: Gate, held: (@Sendable (Petition) -> Void)? = nil) -> Blessed<ScriptedProvider> {
        let doctor = self.doctor
        return Blessed(upstream: model, gate: gate, held: held) { _ in
            Routing(conversationID: "visit-1", recipient: Fixture.patient, reviewers: [doctor.party])
        }
    }

    /// Rules on the first petition that arrives (polling, so a petition held before this task
    /// starts is still found).
    func rule(_ ruling: Ruling, at gate: Gate) -> Task<Void, any Error> {
        Fixture.rule(ruling, as: doctor, at: gate)
    }

    @Test("complete runs the model, holds the draft, waits, and returns the blessed text")
    func complete() async throws {
        let gate = Fixture.gate()
        let reviewer = rule(.bless, at: gate)
        let response = try await blessed(ScriptedProvider(), gate: gate).complete(request)
        try await reviewer.value
        #expect(response.message.content == "Take it with food, twice a day.")
        #expect(response.id == "scripted-1")
        #expect(try await gate.petitions().first?.standing == .blessed)
    }

    @Test("an amended release is what complete returns, never the model's text")
    func amended() async throws {
        let gate = Fixture.gate()
        let reviewer = rule(.amend(content: "Take it with food, twice a day, for all 7 days."), at: gate)
        let out = try await blessed(ScriptedProvider(), gate: gate).blessed(request)
        try await reviewer.value
        #expect(out.response.message.content == "Take it with food, twice a day, for all 7 days.")
        #expect(out.release.basis == .amended)
        #expect(out.petition.proposed.content == "Take it with food, twice a day.")
    }

    @Test("a withheld petition makes complete throw withheld")
    func withheld() async throws {
        let gate = Fixture.gate()
        let reviewer = rule(.withhold(reason: "needs a call"), at: gate)
        await #expect(throws: BlessError.self) { try await blessed(ScriptedProvider(), gate: gate).complete(request) }
        try await reviewer.value
    }

    @Test("stream sends one held delta, then the blessed text and the finish; nothing before the verdict")
    func stream() async throws {
        let gate = Fixture.gate()
        let model = ScriptedProvider(pieces: ["Take it ", "with food."])
        var deltas: [ChatDelta] = []
        var reviewer: Task<Void, any Error>?
        for try await delta in blessed(model, gate: gate).stream(request) {
            deltas.append(delta)
            if let held = delta.held {
                #expect(deltas.count == 1)
                #expect(delta.content == nil)
                let doctor = self.doctor
                reviewer = Task { try await gate.decide(held, .amend(content: "Take it with food, twice a day."), as: doctor) }
            }
        }
        try await reviewer?.value
        #expect(deltas.count == 3)
        #expect(deltas[1].content == "Take it with food, twice a day.")
        #expect(deltas[1].role == .assistant)
        #expect(deltas[2].finishReason == .stop)
        #expect(try await gate.petitions().first?.proposed.content == "Take it with food.")
    }

    @Test("cancelling the stream leaves the petition pending for its reviewer")
    func cancelStream() async throws {
        let gate = Fixture.gate()
        let consumer = Task {
            for try await _ in blessed(ScriptedProvider(), gate: gate).stream(request) {}
        }
        #expect(await eventually { await gate.waiterCount == 1 })
        consumer.cancel()
        _ = try? await consumer.value
        #expect(await eventually { await gate.waiterCount == 0 })
        #expect(try await gate.petitions().map(\.standing) == [.pending])
    }

    @Test("the held hook fires with the petition before the verdict; the provenance names the model")
    func heldHook() async throws {
        let gate = Fixture.gate()
        let seen = RecordingHook()
        let reviewer = rule(.bless, at: gate)
        _ = try await blessed(ScriptedProvider(), gate: gate, held: { seen.record($0) }).complete(request)
        try await reviewer.value
        let petition = try #require(seen.petitions.first)
        #expect(petition.standing == .pending)
        #expect(petition.provenance.provider == "scripted")
        #expect(petition.provenance.model == "test-model")
        #expect(petition.provenance.requestID == "scripted-1")
        #expect(petition.context == [.user("How should I take it?")])
    }

    @Test("a model's failure surfaces and holds nothing")
    func upstreamFails() async throws {
        let gate = Fixture.gate()
        await #expect(throws: Delivery.self) { try await blessed(ScriptedProvider(failure: Delivery()), gate: gate).complete(request) }
        #expect(try await gate.petitions().isEmpty)
    }
}

final class RecordingHook: Sendable {
    private let seen = Synchronization.Mutex<[Petition]>([])
    var petitions: [Petition] { seen.withLock { $0 } }
    func record(_ petition: Petition) { seen.withLock { $0.append(petition) } }
}
