//
//  ChatRequest.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A chat-completion request, provider-neutral: the model, the conversation so far, and
//        the sampling settings most layers share. `extra` carries top-level fields a particular
//        layer needs beside them (Sewn's required `sewn` object, for one).
//

import Foundation

public struct ChatRequest: Codable, Sendable, Equatable {
    public var model: String
    public var messages: [ChatMessage]
    public var temperature: Double?
    public var maxTokens: Int?
    public var extra: [String: JSONValue]?

    public init(model: String, messages: [ChatMessage], temperature: Double? = nil, maxTokens: Int? = nil,
                extra: [String: JSONValue]? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.extra = extra
    }
}
