//
//  InferenceProvider.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The one thing Bless asks of an inference layer: answer a chat request, whole or as a
//        stream. OpenAICompatibleProvider (BlessProviders) speaks the common wire; any other
//        client conforms in a few lines. Blessed is itself an InferenceProvider, so a host swaps
//        `model` for `Blessed(upstream: model, …)` and changes nothing else.
//  PIN:  `stream` has a default over `complete` (one delta with the whole reply), so a layer
//        that cannot stream still conforms; `name` is what a petition's provenance records.
//

import Foundation

public protocol InferenceProvider: Sendable {
    /// The provider's name, as a petition's provenance records it ("mistral", "sewn").
    var name: String { get }
    /// The whole reply.
    func complete(_ request: ChatRequest) async throws -> ChatResponse
    /// The reply as it is written. Cancelling the consumer cancels the request.
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, any Error>
}

extension InferenceProvider {
    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await complete(request)
                    continuation.yield(ChatDelta(role: .assistant, content: response.message.content,
                                                 finishReason: response.finishReason ?? .stop,
                                                 id: response.id, model: response.model))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
