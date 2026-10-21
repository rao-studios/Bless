//
//  ChatResponse.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A completed chat reply, provider-neutral: the provider's id for it, the model that wrote
//        it, the assistant's message, why it stopped, and what it cost in tokens.
//

import Foundation

public enum FinishReason: String, Codable, Sendable {
    case stop
    case length
    case contentFilter = "content_filter"
    case toolCalls = "tool_calls"
    case other

    /// A provider's finish reason; anything unknown reads as `.other`.
    public init(wire: String) {
        self = FinishReason(rawValue: wire) ?? .other
    }

    public init(from decoder: any Decoder) throws {
        self.init(wire: try decoder.singleValueContainer().decode(String.self))
    }
}

public struct ChatResponse: Codable, Sendable, Equatable {
    public struct Usage: Codable, Sendable, Equatable {
        public var promptTokens: Int
        public var completionTokens: Int
        public var totalTokens: Int

        public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }

    public var id: String
    public var model: String
    public var message: ChatMessage
    public var finishReason: FinishReason?
    public var usage: Usage?
    public var created: Date?

    public init(id: String, model: String, message: ChatMessage, finishReason: FinishReason? = .stop,
                usage: Usage? = nil, created: Date? = nil) {
        self.id = id
        self.model = model
        self.message = message
        self.finishReason = finishReason
        self.usage = usage
        self.created = created
    }
}
