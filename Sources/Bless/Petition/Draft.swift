//
//  Draft.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: What a host hands the Gate: the reply the model proposes, the conversation it answers,
//        and where it came from. The Gate keeps only as much of the conversation as the policy's
//        context window allows, and never a system message.
//

import Foundation

/// Who wrote a draft: the provider and model, the provider's id for the reply, and when.
public struct Provenance: Codable, Sendable, Equatable {
    public var provider: String
    public var model: String
    public var requestID: String?
    public var created: Date

    public init(provider: String, model: String, requestID: String? = nil, created: Date = Date()) {
        self.provider = provider
        self.model = model
        self.requestID = requestID
        self.created = Canonical.stamp(created)
    }
}

public struct Draft: Sendable, Equatable {
    /// The host's id for the conversation, so a reviewer can see one patient's thread together.
    public var conversationID: String
    /// The conversation so far, oldest first (the Gate trims it to the policy's window).
    public var context: [ChatMessage]
    /// The reply the model proposes. Its role must be `.assistant`.
    public var proposed: ChatMessage
    public var provenance: Provenance

    public init(conversationID: String, context: [ChatMessage], proposed: ChatMessage, provenance: Provenance) {
        self.conversationID = conversationID
        self.context = context
        self.proposed = proposed
        self.provenance = provenance
    }

    /// The SHA-256 of the proposed text.
    public var digest: Sha256 { .of(proposed.content) }
}
