//
//  SessionFlowTests.swift
//  BlessPlaygroundTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The playground's whole flow with no window and no network: the same Session the app
//        shows, on the offline fake model. A question is held, the reviewer amends it, the
//        patient sees only the amended release, and the ledger verifies; withholding, withdrawing
//        and a lapse each leave the patient a neutral notice and never the draft.
//

import Bless
import BlessPlaygroundKit
import Foundation
import Testing

@MainActor
@Suite("Playground session", .serialized)
struct SessionFlowTests {
    static func session(policy: Policy = Session.defaultPolicy) async -> (Session, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bless-playground-\(UUID())")
        let defaults = UserDefaults(suiteName: "bless-playground-tests-\(UUID())")!
        let session = Session(keys: KeyResolver(store: MemoryKeyStore(), environment: [:], raoKeysFile: nil),
                              identities: ReviewerIdentityStore(file: folder.appendingPathComponent("reviewer.json")),
                              defaults: defaults, launch: LaunchOptions(arguments: ["--provider", "fake"]), fakeDelay: .zero)
        session.policy = policy
        await session.start()
        return (session, folder)
    }

    func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    func ask(_ session: Session, _ scenario: Scenario) async -> Petition? {
        session.seed(scenario)
        session.send()
        guard await until({ if case .held = session.turn { true } else { false } }) else { return nil }
        return session.pending.first
    }

    @Test("a question is held: one pending petition, the draft visible to the operator, nothing to the patient")
    func held() async throws {
        let (session, folder) = await Self.session()
        defer { try? FileManager.default.removeItem(at: folder) }
        let petition = try #require(await ask(session, Scenarios.all[0]))
        #expect(session.pending.count == 1)
        #expect(session.draft.phase == .held)
        #expect(session.draft.text == Scenarios.all[0].fakeReply)
        #expect(session.draft.digest == petition.digest)
        #expect(session.transcript.count == 1)
        #expect(petition.context == [.user(Scenarios.all[0].question)])
        session.stop()
    }

    @Test("an amendment reaches the patient, never the draft; the ledger verifies and the seal checks")
    func amended() async throws {
        let (session, folder) = await Self.session()
        defer { try? FileManager.default.removeItem(at: folder) }
        let petition = try #require(await ask(session, Scenarios.all[0]))
        await session.view(petition.id)
        let amended = "Please avoid ibuprofen with lisinopril. Take paracetamol instead, and call us if it lasts a week."
        await session.decide(.amend(content: amended), on: petition.id, note: "NSAID with an ACE inhibitor")
        #expect(await until { session.turn == .idle })
        guard case .reply(_, let release, _)? = session.transcript.last else { Issue.record("no reply"); return }
        #expect(release.message.content == amended)
        #expect(release.basis == .amended)
        #expect(!session.transcript.contains { if case .reply(_, let r, _) = $0 { r.message.content == Scenarios.all[0].fakeReply } else { false } })
        #expect(session.events.map(\.kind) == [.submitted, .viewed, .decided, .blessed, .released])
        session.verifyLedger()
        #expect(session.chain == .intact(5))
        #expect(Seal.verify(release.verdicts[0], verifyingKey: session.identity.verifyingKey))
        #expect(session.pending.isEmpty)
        #expect(session.decided.first?.standing == .blessed)
        let log = String(decoding: session.exportLedger(), as: UTF8.self)
        #expect(!log.contains("ibuprofen") && !log.contains("NSAID"))
        session.stop()
    }

    @Test("a withholding leaves the patient a neutral notice, never the reason")
    func withheld() async throws {
        let (session, folder) = await Self.session()
        defer { try? FileManager.default.removeItem(at: folder) }
        let petition = try #require(await ask(session, Scenarios.all[2]))
        await session.decide(.withhold(reason: "call her: never double an SSRI"), on: petition.id)
        #expect(await until { session.turn == .idle })
        guard case .notice(_, let text, _)? = session.transcript.last else { Issue.record("no notice"); return }
        #expect(!text.contains("SSRI"))
        #expect(session.draft.phase == .withheld)
        #expect(session.events.last?.kind == .withheld)
        session.stop()
    }

    @Test("withdrawing a held question ends its petition and tells the patient so")
    func withdrawn() async throws {
        let (session, folder) = await Self.session()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try #require(await ask(session, Scenarios.all[1]))
        await session.withdraw()
        #expect(await until { session.turn == .idle })
        #expect(session.draft.phase == .withdrawn)
        #expect(session.events.last?.kind == .withdrawn)
        #expect(session.pending.isEmpty)
        session.stop()
    }

    @Test("a lapse with a holding message sends the fallback, not the draft")
    func lapsed() async throws {
        let (session, folder) = await Self.session(policy: Policy(deadline: .seconds(60), onLapse: .releaseFallback(Session.fallbackText)))
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try #require(await ask(session, Scenarios.all[1]))
        _ = try await session.gate.sweep(now: Date().addingTimeInterval(61))
        #expect(await until { session.turn == .idle })
        guard case .reply(_, let release, _)? = session.transcript.last else { Issue.record("no reply"); return }
        #expect(release.basis == .lapsed)
        #expect(release.message.content == Session.fallbackText)
        session.stop()
    }

    @Test("with no key the session falls back to the offline fake, and Mistral is refused without one")
    func noKey() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bless-playground-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = Session(keys: KeyResolver(store: MemoryKeyStore(), environment: [:], raoKeysFile: nil),
                              identities: ReviewerIdentityStore(file: folder.appendingPathComponent("reviewer.json")),
                              defaults: UserDefaults(suiteName: "bless-playground-tests-\(UUID())")!, fakeDelay: .zero)
        #expect(session.settings.choice == .mistral)
        await session.start()
        #expect(session.settings.choice == .fake)
        #expect(throws: ProviderSetupError.noKey) { try makeProvider(ProviderSettings(), key: nil) }
        session.stop()
    }

    @Test("a conversation carries released replies forward, and never a draft or a notice")
    func conversation() async throws {
        let (session, folder) = await Self.session()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try #require(await ask(session, Scenarios.all[0]))
        await session.decide(.bless, on: first.id)
        #expect(await until { session.turn == .idle })
        let second = try #require(await ask(session, Scenarios.all[2]))
        #expect(second.context == [.user(Scenarios.all[0].question), .assistant(Scenarios.all[0].fakeReply), .user(Scenarios.all[2].question)])
        session.stop()
    }
}
