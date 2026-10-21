//
//  Gate.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where replies wait. `submit` holds a draft as a petition; reviewers `decide` with sealed
//        verdicts; `release(for:)` suspends until the petition is decided and returns the Release
//        (or throws: withheld, expired, withdrawn). Every transition is saved to the petition
//        store and written to the ledger in the same step, and announced to `observe()`rs.
//        Deadlines: `sweep` lapses every due petition; `decide` and `release` lapse a due one on
//        entry; a caller waiting on a petition with a deadline wakes itself when it passes. The
//        Gate owns no timer.
//  PIN:  Every method but `release(for:)` and `dispatch` is free of suspension points (the stores
//        are synchronous), so each transition is atomic on the actor. Waiting is wake-and-recheck:
//        a transition resumes every waiter on that petition with nothing, and each re-reads the
//        store, so many waiters get the same Release and none is resumed twice. Cancelling a
//        waiter only stops that waiter: the petition stays pending (a dropped connection must not
//        cancel the doctor's review), and nothing is written. Only `withdraw` withdraws.
//

import Foundation

public actor Gate {
    public typealias Now = @Sendable () -> Date
    public typealias Sleeper = @Sendable (Duration) async throws -> Void
    public typealias IDs = @Sendable () -> Petition.ID

    /// The audit log of every transition.
    public nonisolated let ledger: Ledger
    private let store: any PetitionStore
    private let now: Now
    private let sleeper: Sleeper
    private let ids: IDs
    private var waiters: [Petition.ID: [UUID: CheckedContinuation<Void, Never>]] = [:]
    private var observers: [UUID: AsyncStream<Petition>.Continuation] = [:]

    /// - Parameters:
    ///   - store: where petitions are kept (memory by default).
    ///   - ledger: where transitions are chained (memory by default).
    ///   - now: the clock; tests pass a fixed one.
    ///   - sleeper: how a waiter sleeps until a deadline; tests pass one that advances `now`.
    ///   - ids: how petitions are named; random by default.
    public init(store: any PetitionStore = MemoryPetitionStore(), ledger: Ledger = Ledger(),
                now: @escaping Now = { Date() }, sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) },
                ids: @escaping IDs = { Petition.ID() }) {
        self.store = store
        self.ledger = ledger
        self.now = now
        self.sleeper = sleeper
        self.ids = ids
    }

    private func stamp() -> Date { Canonical.stamp(now()) }

    // MARK: Holding

    /// Holds a draft for review and returns its petition. Nothing reaches the recipient yet.
    @discardableResult
    public func submit(_ draft: Draft, to recipient: Party, reviewers: [Party], policy: Policy = Policy()) throws -> Petition {
        guard draft.proposed.role == .assistant else { throw BlessError.invalidDraft("the proposed message must be the assistant's") }
        guard !draft.proposed.content.isEmpty else { throw BlessError.invalidDraft("the proposed message is empty") }
        try policy.validate(reviewers: reviewers)
        guard !reviewers.contains(where: { $0.id == recipient.id }) else {
            throw BlessError.invalidPolicy("the recipient cannot review their own reply")
        }
        let at = stamp()
        let petition = Petition(id: ids(), conversationID: draft.conversationID, context: policy.trimmed(draft.context),
                                proposed: draft.proposed, provenance: draft.provenance, recipient: recipient,
                                reviewers: reviewers, policy: policy, submitted: at,
                                deadline: policy.deadlineInterval.map { Canonical.stamp(at.addingTimeInterval($0)) })
        guard try store.load(petition.id) == nil else { throw BlessError.invalidDraft("petition \(petition.id) exists") }
        try store.save(petition)
        try ledger.append(.submitted, petition: petition.id, digest: petition.digest, at: at)
        broadcast(petition)
        return petition
    }

    // MARK: Deciding

    /// Applies a reviewer's verdict (sealed on their device) and returns the petition after it.
    @discardableResult
    public func decide(_ verdict: Verdict) throws -> Petition {
        let at = stamp()
        let petition = try lapseIfDue(verdict.petitionID, at: at)
        guard let reviewer = petition.reviewer(verdict.reviewer) else { throw BlessError.notAReviewer(verdict.reviewer) }
        if let key = reviewer.verifyingKey, verdict.signature != nil {
            guard Seal.verify(verdict, verifyingKey: key) else { throw BlessError.badSeal(reviewer.id) }
        } else if petition.policy.requiresSeal {
            throw BlessError.sealRequired(reviewer.id)
        }
        let next = try petition.applying(verdict, at: at)
        try store.save(next)
        try ledger.append(.decided, petition: next.id, actor: reviewer.id, digest: verdict.endorsed ?? verdict.digest,
                          code: verdict.ruling.kind.rawValue, at: at)
        switch next.standing {
        case .blessed: try ledger.append(.blessed, petition: next.id, digest: next.digest, at: at)
        case .withheld: try ledger.append(.withheld, petition: next.id, actor: reviewer.id, digest: verdict.digest, at: at)
        case .pending, .expired, .withdrawn: break
        }
        transition(next)
        return next
    }

    /// Seals the ruling with the reviewer's key, on the petition's current text, and applies it.
    @discardableResult
    public func decide(_ id: Petition.ID, _ ruling: Ruling, as reviewer: ReviewerIdentity, note: String? = nil) throws -> Petition {
        let petition = try lapseIfDue(id, at: stamp())
        return try decide(try reviewer.verdict(ruling, on: petition, note: note, issued: now()))
    }

    /// Applies an unsealed ruling; refused with `.sealRequired` when the policy requires seals.
    @discardableResult
    public func decide(_ id: Petition.ID, _ ruling: Ruling, by reviewer: Party.ID, note: String? = nil) throws -> Petition {
        let petition = try lapseIfDue(id, at: stamp())
        return try decide(Verdict(petitionID: id, reviewer: reviewer, ruling: ruling, digest: petition.digest, note: note,
                                  issued: now()))
    }

    /// Records that a reviewer opened the petition.
    public func markViewed(_ id: Petition.ID, by reviewer: Party.ID) throws {
        let at = stamp()
        let petition = try lapseIfDue(id, at: at)
        guard petition.reviewer(reviewer) != nil else { throw BlessError.notAReviewer(reviewer) }
        try ledger.append(.viewed, petition: id, actor: reviewer, digest: petition.digest, at: at)
    }

    /// Ends a pending petition without a decision (the recipient left, the host cancelled).
    @discardableResult
    public func withdraw(_ id: Petition.ID) throws -> Petition {
        let at = stamp()
        var petition = try lapseIfDue(id, at: at)
        guard petition.standing == .pending else { throw BlessError.alreadyDecided(id, petition.standing) }
        petition.standing = .withdrawn
        petition.decided = at
        try store.save(petition)
        try ledger.append(.withdrawn, petition: id, digest: petition.digest, at: at)
        transition(petition)
        return petition
    }

    /// Lapses every pending petition whose deadline has passed (by `now`, or the Gate's clock)
    /// and returns them.
    @discardableResult
    public func sweep(now date: Date? = nil) throws -> [Petition] {
        let at = Canonical.stamp(date ?? now())
        var lapsed: [Petition] = []
        for petition in try store.all() where petition.standing == .pending {
            let after = try lapseIfDue(petition.id, at: at)
            if after.standing != .pending { lapsed.append(after) }
        }
        return lapsed
    }

    // MARK: Releasing

    /// Waits until the petition is decided, then returns its Release. Throws `.withheld`,
    /// `.expired` or `.withdrawn` when there is nothing to release, and CancellationError when
    /// the caller is cancelled (the petition stays pending).
    public func release(for id: Petition.ID) async throws -> Release {
        while true {
            try Task.checkCancellation()
            let petition = try lapseIfDue(id, at: stamp())
            switch petition.standing {
            case .pending:
                try await park(id, deadline: petition.policy.onLapse == .hold ? nil : petition.deadline)
            case .blessed:
                return try issue(petition)
            case .expired:
                guard petition.fallback != nil else { throw BlessError.expired(id) }
                return try issue(petition)
            case .withheld:
                throw BlessError.withheld(id, reason: petition.withheldReason ?? "")
            case .withdrawn:
                throw BlessError.withdrawn(id)
            }
        }
    }

    /// Delivers a decided petition's Release through the host's dispatcher, after verifying it,
    /// and records the outcome.
    @discardableResult
    public func dispatch(_ id: Petition.ID, via dispatcher: some Dispatcher) async throws -> Release {
        let petition = try lapseIfDue(id, at: stamp())
        guard petition.standing == .blessed || petition.fallback != nil else { throw BlessError.notBlessed(id) }
        let release = try issue(petition)
        guard let current = try store.load(id) else { throw BlessError.unknownPetition(id) }
        try release.verify(against: current)
        do {
            try await dispatcher.dispatch(release, to: current.recipient)
        } catch {
            try ledger.append(.failed, petition: id, actor: current.recipient.id, digest: release.digest,
                              code: (error as? BlessError)?.code ?? "dispatcher", at: stamp())
            throw error
        }
        try ledger.append(.dispatched, petition: id, actor: current.recipient.id, digest: release.digest, at: stamp())
        return release
    }

    // MARK: Reading

    /// The petition as it stands (lapsed first, if it is due).
    public func petition(_ id: Petition.ID) throws -> Petition {
        try lapseIfDue(id, at: stamp())
    }

    /// The petitions still waiting, for one reviewer or for all, oldest first.
    public func pending(for reviewer: Party.ID? = nil) throws -> [Petition] {
        try sweep()
        return try store.all().filter { petition in
            petition.standing == .pending && (reviewer.map { petition.reviewer($0) != nil } ?? true)
        }
    }

    /// Every petition, oldest first.
    public func petitions() throws -> [Petition] {
        try store.all()
    }

    /// Every petition as it changes: submitted, decided, lapsed, withdrawn, released.
    public func observe() -> AsyncStream<Petition> {
        let (stream, continuation) = AsyncStream.makeStream(of: Petition.self, bufferingPolicy: .unbounded)
        let token = UUID()
        observers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopObserving(token) }
        }
        return stream
    }

    /// How many callers are waiting in `release(for:)` (tests check none are left behind).
    var waiterCount: Int { waiters.values.reduce(0) { $0 + $1.count } }

    // MARK: Internals

    private func lapseIfDue(_ id: Petition.ID, at: Date) throws -> Petition {
        guard let petition = try store.load(id) else { throw BlessError.unknownPetition(id) }
        guard let lapsed = petition.lapsed(at: at) else { return petition }
        try store.save(lapsed)
        try ledger.append(.expired, petition: id, digest: lapsed.digest, code: lapsed.policy.onLapse.name, at: at)
        transition(lapsed)
        return lapsed
    }

    /// The petition's Release, stamping and logging it the first time it is handed out.
    private func issue(_ petition: Petition) throws -> Release {
        if let released = petition.released {
            guard let release = Release(petition: petition, at: released) else { throw BlessError.notBlessed(petition.id) }
            return release
        }
        var next = petition
        let at = stamp()
        next.released = at
        guard let release = Release(petition: next, at: at) else { throw BlessError.notBlessed(petition.id) }
        try store.save(next)
        try ledger.append(.released, petition: next.id, digest: release.digest, code: release.basis.rawValue, at: at)
        broadcast(next)
        return release
    }

    private func transition(_ petition: Petition) {
        broadcast(petition)
        if petition.isTerminal { wakeAll(petition.id) }
    }

    private func broadcast(_ petition: Petition) {
        for observer in observers.values { observer.yield(petition) }
    }

    private func stopObserving(_ token: UUID) {
        observers[token] = nil
    }

    /// Suspends until the petition changes, the deadline passes, or the caller is cancelled.
    private func park(_ id: Petition.ID, deadline: Date?) async throws {
        let token = UUID()
        guard let deadline else {
            await wait(id, token)
            try Task.checkCancellation()
            return
        }
        let delay = max(0, deadline.timeIntervalSince(now()))
        let sleeper = self.sleeper
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await self.wait(id, token) }
            group.addTask { try await sleeper(.milliseconds(Int64((delay * 1000).rounded(.up)))) }
            _ = try await group.next()
            group.cancelAll()
        }
        try Task.checkCancellation()
    }

    private func wait(_ id: Petition.ID, _ token: UUID) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[id, default: [:]][token] = continuation
                }
            }
        } onCancel: {
            Task { await self.wake(id, token) }
        }
    }

    private func wake(_ id: Petition.ID, _ token: UUID) {
        guard let continuation = waiters[id]?.removeValue(forKey: token) else { return }
        if waiters[id]?.isEmpty == true { waiters[id] = nil }
        continuation.resume()
    }

    private func wakeAll(_ id: Petition.ID) {
        for continuation in (waiters.removeValue(forKey: id) ?? [:]).values { continuation.resume() }
    }
}
