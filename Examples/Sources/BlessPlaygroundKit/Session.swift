//
//  Session.swift
//  BlessPlaygroundKit
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The one store the four panes share: a patient, a model and a reviewer at one Gate.
//        `send()` is the pattern itself: the model (wrapped in Witnessed, so the Model pane can
//        watch it write) is wrapped in Blessed, and the patient's turn waits for a Release
//        exactly as a host's would. The Reviewer pane rules with the session's signing identity;
//        the Ledger pane reads the Gate's ledger. Nothing the patient sees comes from anywhere but
//        a Release, or a neutral notice when there is none.
//  PIN:  Main-actor state; every Gate call is an await, and key lookups (which spawn
//        /usr/bin/security) run off the main actor. The deadline sweeper runs once a second and
//        only while something is pending. Policy edits apply to the next question.
//

import Bless
import BlessProviders
import Foundation
import Observation

/// What the app was launched with: `--provider fake|mistral|openai-compatible`, `--model <id>`,
/// `--scenario <id>`. Unknown arguments are ignored (Xcode adds its own).
public struct LaunchOptions: Sendable, Equatable {
    public var provider: ProviderChoice?
    public var model: String?
    public var scenario: Scenario?

    public init(arguments: [String] = []) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        provider = value("--provider").flatMap(ProviderChoice.init(rawValue:))
        model = value("--model")
        scenario = value("--scenario").flatMap(Scenarios.named)
    }
}

@MainActor
@Observable
public final class Session {
    /// One line of the patient's transcript.
    public enum Entry: Identifiable, Equatable, Sendable {
        case patient(id: UUID, text: String, at: Date)
        case reply(id: UUID, release: Release, reviewer: String)
        case notice(id: UUID, text: String, at: Date)

        public var id: UUID {
            switch self {
            case .patient(let id, _, _), .reply(let id, _, _), .notice(let id, _, _): id
            }
        }
    }

    /// Where the patient's current question stands.
    public enum Turn: Equatable, Sendable {
        case idle
        case drafting
        case held(Petition.ID, since: Date)
    }

    public enum ChainStatus: Equatable, Sendable {
        case unchecked
        case intact(Int)
        case broken(seq: Int)
    }

    public enum KeyCheck: Equatable, Sendable {
        case unchecked, checking
        case passed(models: Int)
        case failed(String)
    }

    public let patient = Party(id: "patient-ada", displayName: "Ada Moreno")
    public let gate: Gate

    public private(set) var identity: ReviewerIdentity
    public private(set) var transcript: [Entry] = []
    public private(set) var turn: Turn = .idle
    public private(set) var draft = DraftState()
    public private(set) var pending: [Petition] = []
    public private(set) var decided: [Petition] = []
    public private(set) var events: [LedgerEvent] = []
    public private(set) var chain: ChainStatus = .unchecked
    public private(set) var keySource: KeySource?
    public private(set) var keyCheck: KeyCheck = .unchecked
    public private(set) var reviewerError: String?
    public private(set) var conversationID = Session.newConversationID()
    public var composer = ""
    public var policy: Policy { didSet { save(policy, as: Self.policyKey) } }
    public var settings: ProviderSettings {
        didSet {
            save(settings, as: Self.settingsKey)
            keyCheck = .unchecked
        }
    }

    @ObservationIgnored private let keys: KeyResolver
    @ObservationIgnored private let identities: ReviewerIdentityStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fakeDelay: Duration
    @ObservationIgnored private var resolved: ResolvedKey?
    @ObservationIgnored private var viewed: Set<Petition.ID> = []
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var sweeper: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    static let settingsKey = "providerSettings"
    static let policyKey = "policy"
    public static let fallbackText = "Your care team has your message and will reply as soon as they can."
    public static let defaultPolicy = Policy(deadline: .seconds(180), onLapse: .releaseFallback(fallbackText), contextWindow: 8)

    public init(keys: KeyResolver = .live(), identities: ReviewerIdentityStore = .live(), defaults: UserDefaults = .standard,
                launch: LaunchOptions = LaunchOptions(), gate: Gate = Gate(), fakeDelay: Duration = .milliseconds(45)) {
        self.keys = keys
        self.identities = identities
        self.defaults = defaults
        self.gate = gate
        self.fakeDelay = fakeDelay
        self.identity = (try? identities.loadOrCreate()) ?? ReviewerIdentity(id: "dr-okafor", displayName: "Dr. Okafor")
        var settings = Self.load(ProviderSettings.self, from: defaults, key: Self.settingsKey) ?? ProviderSettings()
        if let provider = launch.provider {
            settings.choice = provider
            settings.model = provider.models[0]
        }
        if let model = launch.model { settings.model = model }
        self.settings = settings
        self.policy = Self.load(Policy.self, from: defaults, key: Self.policyKey) ?? Self.defaultPolicy
        if let scenario = launch.scenario { composer = scenario.question }
    }

    // MARK: Lifecycle

    /// Starts watching the Gate, sweeping deadlines, and looking up the key.
    public func start() async {
        guard observation == nil else { return }
        let updates = await gate.observe()
        observation = Task { [weak self] in
            for await petition in updates {
                self?.observed(petition)
            }
        }
        sweeper = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.pending.isEmpty else { continue }
                _ = try? await self.gate.sweep()
            }
        }
        await refreshKey()
        if keySource == nil, settings.choice.needsKey { settings = ProviderSettings(choice: .fake, model: FakeProvider.model) }
        refreshLedger()
    }

    public func stop() {
        observation?.cancel()
        sweeper?.cancel()
        inFlight?.cancel()
        observation = nil
    }

    // MARK: The patient's turn: the pattern

    public var canSend: Bool {
        turn == .idle && !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sends the composer's question through Blessed(Witnessed(model)).
    public func send() {
        let question = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard turn == .idle, !question.isEmpty else { return }
        composer = ""
        transcript.append(.patient(id: UUID(), text: question, at: Date()))
        let upstream: any InferenceProvider
        do {
            upstream = try makeProvider(settings, key: resolved?.secret, fakeDelay: fakeDelay)
        } catch {
            draft = DraftState()
            draft.phase = .failed(String(describing: error))
            notice("The question could not be sent. Please try again.")
            return
        }
        turn = .drafting
        let request = ChatRequest(model: settings.model, messages: [.system(Scenarios.systemPrompt)] + conversation(),
                                  temperature: 0.3, maxTokens: 400)
        let routing = Routing(conversationID: conversationID, recipient: patient, reviewers: [identity.party], policy: policy)
        let witnessed = Witnessed(upstream: upstream) { [weak self] event in self?.draft.apply(event) }
        let blessed = Blessed(upstream: witnessed, gate: gate) { _ in routing }
        let reviewerName = identity.party.displayName
        inFlight = Task { [weak self] in
            do {
                let out = try await blessed.blessed(request)
                self?.received(out.release, reviewer: reviewerName)
            } catch {
                self?.ended(error)
            }
        }
    }

    /// Takes the question back: withdraws a held petition, or stops the draft.
    public func withdraw() async {
        if case .held(let id, _) = turn {
            _ = try? await gate.withdraw(id)
        } else {
            inFlight?.cancel()
        }
    }

    /// Fills the composer with a scenario's question.
    public func seed(_ scenario: Scenario) {
        composer = scenario.question
    }

    /// A new visit: a fresh conversation and transcript; the ledger and the reviewer's history stay.
    public func newVisit() {
        guard turn == .idle else { return }
        transcript = []
        draft = DraftState()
        conversationID = Self.newConversationID()
    }

    // MARK: The reviewer

    /// The conversation the policy lets the reviewer see, as the petition keeps it.
    public func context(for petition: Petition) -> [ChatMessage] { petition.context }

    /// Records that the reviewer opened a petition (once each).
    public func view(_ id: Petition.ID) async {
        guard !viewed.contains(id) else { return }
        viewed.insert(id)
        try? await gate.markViewed(id, by: identity.party.id)
        refreshLedger()
    }

    /// Rules on a petition with the session's sealed identity.
    public func decide(_ ruling: Ruling, on id: Petition.ID, note: String? = nil) async {
        reviewerError = nil
        do {
            try await gate.decide(id, ruling, as: identity, note: note?.isEmpty == true ? nil : note)
        } catch {
            reviewerError = String(describing: error)
        }
        refreshLedger()
    }

    public func renameReviewer(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let renamed = try? identities.rename(identity, to: trimmed) else { return }
        identity = renamed
    }

    /// A new signing key. Petitions held under the old key keep naming it.
    public func regenerateIdentity() {
        if let fresh = try? identities.regenerate(displayName: identity.party.displayName) { identity = fresh }
    }

    // MARK: The ledger

    public func verifyLedger() {
        do {
            chain = .intact(try gate.ledger.verify())
        } catch BlessError.ledgerTampered(let seq) {
            chain = .broken(seq: seq)
        } catch {
            chain = .broken(seq: 0)
        }
    }

    public func exportLedger() -> Data {
        (try? gate.ledger.jsonLines()) ?? Data()
    }

    // MARK: The key

    /// Looks up the key again (off the main actor: it runs /usr/bin/security).
    public func refreshKey() async {
        let keys = self.keys
        resolved = await Task.detached { keys.resolve() }.value
        keySource = resolved?.source
    }

    public func saveKey(_ text: String) async throws {
        guard let secret = Secret(text) else { return }
        let store = keys.store
        try await Task.detached { try store.write(secret) }.value
        await refreshKey()
    }

    public func forgetKey() async throws {
        let store = keys.store
        try await Task.detached { try store.forget() }.value
        await refreshKey()
    }

    /// Asks the provider which models the key can use.
    public func checkKey() async {
        keyCheck = .checking
        guard settings.choice != .fake else { return keyCheck = .passed(models: 1) }
        let preset: Preset
        if settings.choice == .mistral {
            preset = .mistral
        } else if let url = URL(string: settings.baseURL), url.scheme != nil {
            preset = .custom(name: "openai-compatible", baseURL: url)
        } else {
            return keyCheck = .failed(ProviderSetupError.badURL(settings.baseURL).description)
        }
        do {
            let models = try await OpenAICompatibleProvider(preset: preset, apiKey: resolved?.secret.value).models()
            keyCheck = .passed(models: models.count)
        } catch {
            keyCheck = .failed(String(describing: error))
        }
    }

    // MARK: Internals

    private func conversation() -> [ChatMessage] {
        transcript.compactMap { entry in
            switch entry {
            case .patient(_, let text, _): .user(text)
            case .reply(_, let release, _): release.message
            case .notice: nil
            }
        }
    }

    private func observed(_ petition: Petition) {
        if petition.standing == .pending {
            if let index = pending.firstIndex(where: { $0.id == petition.id }) {
                pending[index] = petition
            } else {
                pending.append(petition)
            }
            if turn == .drafting, petition.conversationID == conversationID, petition.proposed.content == draft.text {
                turn = .held(petition.id, since: petition.submitted)
                draft.phase = .held
            }
        } else {
            pending.removeAll { $0.id == petition.id }
            decided.removeAll { $0.id == petition.id }
            decided.insert(petition, at: 0)
            if decided.count > 20 { decided.removeLast() }
        }
        refreshLedger()
    }

    private func received(_ release: Release, reviewer: String) {
        transcript.append(.reply(id: UUID(), release: release, reviewer: reviewer))
        draft.phase = .released(release.basis)
        turn = .idle
        refreshLedger()
    }

    private func ended(_ error: any Error) {
        switch error {
        case BlessError.withheld:
            draft.phase = .withheld
            notice("Your care team will contact you about this question directly.")
        case BlessError.expired:
            draft.phase = .lapsed
            notice("Your care team hasn't been able to review this yet. They'll be in touch.")
        case BlessError.withdrawn, is CancellationError:
            draft.phase = .withdrawn
            notice("You withdrew this question.")
        default:
            if case .failed = draft.phase {} else { draft.phase = .failed(String(describing: error)) }
            notice("Something went wrong sending your question. Please try again.")
        }
        turn = .idle
        refreshLedger()
    }

    private func notice(_ text: String) {
        transcript.append(.notice(id: UUID(), text: text, at: Date()))
    }

    private func refreshLedger() {
        events = (try? gate.ledger.events()) ?? []
        if chain != .unchecked { verifyLedger() }
    }

    private func save(_ value: some Encodable, as key: String) {
        if let data = try? JSONCoding.encoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONCoding.decoder().decode(T.self, from: $0) }
    }

    private static func newConversationID() -> String {
        "visit-" + UUID().uuidString.prefix(8).lowercased()
    }
}
