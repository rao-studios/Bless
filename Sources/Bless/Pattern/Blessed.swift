//
//  Blessed.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The pattern, as one InferenceProvider. Wrap a model in Blessed and every reply it
//        writes is held at the Gate as a petition; `complete` returns only once a reviewer has
//        blessed (or amended) it, with the blessed text in place of the model's. A host that
//        calls `model.complete(request)` today calls `blessed.complete(request)` instead and
//        changes nothing else. `route` says, per request, whose conversation it is, who
//        receives the reply, who reviews it and under which policy.
//  PIN:  Nothing streams until it is blessed: `stream` reads the model's stream to its end,
//        holds the whole reply, sends one delta carrying only the petition's id, waits, then
//        sends the blessed text. Cancelling the consumer cancels the wait, not the review.
//

import Foundation

/// Who a request's reply is for and who must bless it.
public struct Routing: Sendable {
    public var conversationID: String
    public var recipient: Party
    public var reviewers: [Party]
    public var policy: Policy

    public init(conversationID: String, recipient: Party, reviewers: [Party], policy: Policy = Policy()) {
        self.conversationID = conversationID
        self.recipient = recipient
        self.reviewers = reviewers
        self.policy = policy
    }
}

/// A blessed reply with the record behind it.
public struct BlessedResponse: Sendable {
    /// The reply as the host should deliver it: the Release's text under the model's id.
    public var response: ChatResponse
    /// The petition, as decided.
    public var petition: Petition
    public var release: Release
}

public struct Blessed<Upstream: InferenceProvider>: InferenceProvider {
    public let upstream: Upstream
    public let gate: Gate
    private let route: @Sendable (ChatRequest) throws -> Routing
    private let held: (@Sendable (Petition) -> Void)?

    /// - Parameters:
    ///   - upstream: the model whose replies are held.
    ///   - gate: where they wait.
    ///   - held: called with each petition as soon as it is held (page the reviewer here).
    ///   - route: the conversation, recipient, reviewers and policy for a request.
    public init(upstream: Upstream, gate: Gate, held: (@Sendable (Petition) -> Void)? = nil,
                route: @escaping @Sendable (ChatRequest) throws -> Routing) {
        self.upstream = upstream
        self.gate = gate
        self.held = held
        self.route = route
    }

    public var name: String { "blessed(\(upstream.name))" }

    /// The blessed reply, with its petition and release.
    public func blessed(_ request: ChatRequest) async throws -> BlessedResponse {
        let routing = try route(request)
        let draft = try await upstream.complete(request)
        return try await hold(draft, for: request, routing: routing)
    }

    /// The reply, once blessed: the Release's text under the model's id.
    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        try await blessed(request).response
    }

    /// One `held` delta, then the blessed text and the finish. Nothing of the draft is streamed.
    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let routing = try route(request)
                    let draft = try await upstream.stream(request).assembled(model: request.model)
                    let out = try await hold(draft, for: request, routing: routing) { petition in
                        continuation.yield(ChatDelta(held: petition.id))
                    }
                    continuation.yield(ChatDelta(role: .assistant, content: out.response.message.content,
                                                 id: out.response.id, model: out.response.model))
                    continuation.yield(ChatDelta(finishReason: out.response.finishReason ?? .stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func hold(_ draft: ChatResponse, for request: ChatRequest, routing: Routing,
                      announce: (@Sendable (Petition) -> Void)? = nil) async throws -> BlessedResponse {
        let petition = try await gate.submit(
            Draft(conversationID: routing.conversationID, context: request.messages,
                  proposed: .assistant(draft.message.content),
                  provenance: Provenance(provider: upstream.name, model: draft.model, requestID: draft.id,
                                         created: draft.created ?? Date())),
            to: routing.recipient, reviewers: routing.reviewers, policy: routing.policy)
        held?(petition)
        announce?(petition)
        let release = try await gate.release(for: petition.id)
        let decided = try await gate.petition(petition.id)
        let response = ChatResponse(id: draft.id, model: draft.model, message: release.message,
                                    finishReason: release.basis == .blessed ? draft.finishReason : .stop,
                                    usage: draft.usage, created: draft.created)
        return BlessedResponse(response: response, petition: decided, release: release)
    }
}
