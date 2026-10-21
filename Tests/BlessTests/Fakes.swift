//
//  Fakes.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: What the suites share: a scripted model, a clock tests move by hand (and sleepers that
//        advance it or stall), a recording dispatcher, fixed reviewers with fixed keys, a draft,
//        and `eventually` for waiting on another task without a fixed sleep.
//

import Foundation
import Synchronization
@testable import Bless

/// A model that answers with fixed text, whole or in pieces, and remembers what it was asked.
final class ScriptedProvider: InferenceProvider {
    let name = "scripted"
    let reply: String
    let pieces: [String]?
    let failure: (any Error)?
    private let asked = Mutex<[ChatRequest]>([])

    init(reply: String = "Take it with food, twice a day.", pieces: [String]? = nil, failure: (any Error)? = nil) {
        self.reply = reply
        self.pieces = pieces
        self.failure = failure
    }

    var requests: [ChatRequest] { asked.withLock { $0 } }

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        asked.withLock { $0.append(request) }
        if let failure { throw failure }
        return ChatResponse(id: "scripted-1", model: request.model, message: .assistant(reply), finishReason: .stop,
                            usage: .init(promptTokens: 10, completionTokens: 8, totalTokens: 18),
                            created: Date(timeIntervalSince1970: 1_760_961_600))
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, any Error> {
        asked.withLock { $0.append(request) }
        let pieces = self.pieces ?? [reply]
        let failure = self.failure
        return AsyncThrowingStream { continuation in
            if let failure { return continuation.finish(throwing: failure) }
            for (index, piece) in pieces.enumerated() {
                continuation.yield(ChatDelta(role: index == 0 ? .assistant : nil, content: piece,
                                             id: "scripted-1", model: request.model))
            }
            continuation.yield(ChatDelta(finishReason: .stop))
            continuation.finish()
        }
    }
}

/// A clock that moves only when told to.
final class FakeClock: Sendable {
    private let date: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_760_961_600)) {
        date = Mutex(start)
    }

    var current: Date { date.withLock { $0 } }

    var now: Gate.Now { { [self] in current } }

    func advance(_ duration: Duration) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    /// Sleeps by moving the clock, at once: a waiter with a deadline wakes as if it had passed.
    var advancing: Gate.Sleeper { { [self] duration in advance(duration) } }

    /// Sleeps until cancelled: deadlines pass only when a test moves the clock and sweeps.
    static let stalled: Gate.Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }
}

/// Petition ids in order: p-1, p-2, ...
final class Counter: Sendable {
    private let next = Mutex(0)
    var ids: Gate.IDs { { [self] in Petition.ID("p-\(next.withLock { $0 += 1; return $0 })") } }
}

final class RecordingDispatcher: Dispatcher {
    private let sent = Mutex<[Release]>([])
    let failure: (any Error)?

    init(failure: (any Error)? = nil) { self.failure = failure }

    var releases: [Release] { sent.withLock { $0 } }

    func dispatch(_ release: Release, to recipient: Party) async throws {
        if let failure { throw failure }
        sent.withLock { $0.append(release) }
    }
}

struct Delivery: Error, Equatable {}

enum Fixture {
    static let patient = Party(id: "patient-ada", displayName: "Ada")

    /// A reviewer with a fixed key, so seals and fingerprints are the same every run.
    static func reviewer(_ n: Int, name: String? = nil) -> ReviewerIdentity {
        try! ReviewerIdentity(id: Party.ID("dr-\(n)"), displayName: name ?? "Dr. \(n)",
                              privateKey: Data(repeating: UInt8(n), count: 32))
    }

    static func draft(_ text: String = "Take it with food, twice a day.", conversation: String = "visit-1") -> Draft {
        Draft(conversationID: conversation,
              context: [.system("You draft replies for a clinician."), .user("How should I take amoxicillin?"),
                        .assistant("Is this your first course?"), .user("Yes, the first.")],
              proposed: .assistant(text),
              provenance: Provenance(provider: "scripted", model: "test-model", requestID: "req-1",
                                     created: Date(timeIntervalSince1970: 1_760_961_600)))
    }

    static func gate(clock: FakeClock = FakeClock(), sleeper: Gate.Sleeper? = nil, store: (any PetitionStore)? = nil,
                     ledger: Ledger = Ledger()) -> Gate {
        Gate(store: store ?? MemoryPetitionStore(), ledger: ledger, now: clock.now,
             sleeper: sleeper ?? FakeClock.stalled, ids: Counter().ids)
    }
}

extension Fixture {
    /// A reviewer who rules on the first pending petition, polling for up to five seconds.
    static func rule(_ ruling: Ruling, as reviewer: ReviewerIdentity, at gate: Gate) -> Task<Void, any Error> {
        Task {
            let clock = ContinuousClock()
            let end = clock.now + .seconds(5)
            while clock.now < end {
                if let petition = try await gate.pending(for: reviewer.party.id).first {
                    try await gate.decide(petition.id, ruling, as: reviewer)
                    return
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            throw BlessError.unknownPetition("none arrived")
        }
    }
}

/// Polls until the condition holds or two seconds pass; returns whether it held.
func eventually(_ timeout: Duration = .seconds(2), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + timeout
    while clock.now < end {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return try await condition()
}
