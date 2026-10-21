//
//  Witnessed.swift
//  BlessPlaygroundKit
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A provider that lets the operator watch the draft being written: it reads the model's
//        stream, hands each piece to the Model pane, and returns the whole reply to Blessed,
//        which holds it. The patient sees none of this; only the Release reaches the Patient pane.
//        This composition is the demo's point: Blessed needs no UI hook, any provider can be
//        wrapped, and the wrapper is itself a provider.
//  PIN:  Not generic: it holds `any InferenceProvider`, so Blessed<Witnessed> is one concrete type
//        whichever model the settings pick.
//

import Bless
import Foundation

public enum DraftEvent: Sendable {
    case began(model: String, at: Date)
    case delta(String)
    case finished(ChatResponse, at: Date)
    case failed(String)
}

public struct Witnessed: InferenceProvider {
    public let upstream: any InferenceProvider
    private let onEvent: @MainActor @Sendable (DraftEvent) -> Void

    public init(upstream: any InferenceProvider, onEvent: @escaping @MainActor @Sendable (DraftEvent) -> Void) {
        self.upstream = upstream
        self.onEvent = onEvent
    }

    public var name: String { upstream.name }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        await onEvent(.began(model: request.model, at: Date()))
        var text = ""
        var id: String?
        var model: String?
        var finish: FinishReason?
        do {
            for try await delta in upstream.stream(request) {
                id = id ?? delta.id
                model = model ?? delta.model
                finish = delta.finishReason ?? finish
                if let piece = delta.content, !piece.isEmpty {
                    text += piece
                    await onEvent(.delta(piece))
                }
            }
        } catch {
            await onEvent(.failed(String(describing: error)))
            throw error
        }
        guard !text.isEmpty else {
            await onEvent(.failed("the model returned an empty reply"))
            throw BlessError.invalidDraft("the model returned an empty reply")
        }
        let response = ChatResponse(id: id ?? "draft-\(UUID().uuidString.prefix(8).lowercased())", model: model ?? request.model,
                                    message: .assistant(text), finishReason: finish ?? .stop, created: Date())
        await onEvent(.finished(response, at: Date()))
        return response
    }
}

/// What the Model pane shows of the current draft.
public struct DraftState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle, drafting, held, released(Release.Basis), withheld, lapsed, withdrawn, failed(String)

        public var label: String {
            switch self {
            case .idle: "Idle"
            case .drafting: "Drafting"
            case .held: "Held for review"
            case .released(.blessed): "Released as written"
            case .released(.amended): "Released, amended"
            case .released(.lapsed): "Lapsed: fallback sent"
            case .withheld: "Withheld"
            case .lapsed: "Lapsed: nothing sent"
            case .withdrawn: "Withdrawn"
            case .failed: "Failed"
            }
        }
    }

    public var phase: Phase = .idle
    public var text = ""
    public var model = ""
    public var requestID: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var digest: Sha256?

    public init() {}

    public mutating func apply(_ event: DraftEvent) {
        switch event {
        case .began(let model, let at):
            self = DraftState()
            self.phase = .drafting
            self.model = model
            self.startedAt = at
        case .delta(let piece):
            text += piece
        case .finished(let response, let at):
            text = response.message.content
            model = response.model
            requestID = response.id
            finishedAt = at
            digest = .of(response.message.content)
        case .failed(let why):
            phase = .failed(why)
            finishedAt = Date()
        }
    }

    /// Seconds from the first request to the last token.
    public var latency: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}
