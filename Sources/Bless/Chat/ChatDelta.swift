//
//  ChatDelta.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: One piece of a streamed reply. A provider's stream is a run of deltas whose `content`
//        concatenates to the reply. `held` is Bless's own: Blessed's stream sends one delta
//        carrying only the petition's id when the reply is held for review, before anything
//        else, so a client can say "waiting for your doctor" without seeing a word of the draft.
//

import Foundation

public struct ChatDelta: Sendable, Equatable {
    public var role: ChatRole?
    public var content: String?
    public var finishReason: FinishReason?
    /// The provider's id for the reply, when its stream names one.
    public var id: String?
    /// The model writing the reply, when its stream names one.
    public var model: String?
    /// Set only by Blessed: the reply is held as this petition. Never carries content.
    public var held: Petition.ID?

    public init(role: ChatRole? = nil, content: String? = nil, finishReason: FinishReason? = nil,
                id: String? = nil, model: String? = nil, held: Petition.ID? = nil) {
        self.role = role
        self.content = content
        self.finishReason = finishReason
        self.id = id
        self.model = model
        self.held = held
    }
}

extension AsyncThrowingStream where Element == ChatDelta, Failure == any Error {
    /// The whole reply a stream spells out, read to its end. `model` names the model when the
    /// stream does not.
    public func assembled(model: String) async throws -> ChatResponse {
        var text = ""
        var finish: FinishReason?
        var id: String?
        var seen: String?
        for try await delta in self {
            text += delta.content ?? ""
            finish = delta.finishReason ?? finish
            id = id ?? delta.id
            seen = seen ?? delta.model
        }
        return ChatResponse(id: id ?? "stream-\(UUID().uuidString.lowercased())", model: seen ?? model,
                            message: .assistant(text), finishReason: finish ?? .stop)
    }
}
