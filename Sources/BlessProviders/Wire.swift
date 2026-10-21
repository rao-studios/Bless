//
//  Wire.swift
//  BlessProviders
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The chat-completions wire every mainstream layer shares, and its mapping to Bless's
//        neutral types: a request with snake_case keys and the preset's and request's `extra`
//        fields merged at the top level; a response's `choices[0].message`; a stream chunk's
//        `choices[0].delta`.
//  PIN:  `content` may be a string, null, or (Mistral's reasoning models) an array of typed parts;
//        only `text` parts are read. Sewn's `refusal` and unknown fields are ignored.
//

import Bless
import Foundation

enum Wire {
    struct Message: Codable {
        var role: String
        var content: Content?
    }

    /// A message's content as the wire writes it.
    struct Content: Codable {
        var text: String

        init(_ text: String) { self.text = text }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self.text = text
            } else {
                let parts = try container.decode([Part].self)
                self.text = parts.filter { $0.type == "text" }.compactMap(\.text).joined()
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(text)
        }

        struct Part: Decodable {
            var type: String
            var text: String?
        }
    }

    struct Request: Encodable {
        var model: String
        var messages: [Message]
        var temperature: Double?
        var maxTokens: Int?
        var stream: Bool
        var extra: [String: JSONValue]

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ string: String) { stringValue = string }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        static let standard: Set<String> = ["model", "messages", "temperature", "max_tokens", "stream"]

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(model, forKey: Key("model"))
            try c.encode(messages, forKey: Key("messages"))
            try c.encodeIfPresent(temperature, forKey: Key("temperature"))
            try c.encodeIfPresent(maxTokens, forKey: Key("max_tokens"))
            try c.encode(stream, forKey: Key("stream"))
            for (key, value) in extra where !Self.standard.contains(key) {
                try c.encode(value, forKey: Key(key))
            }
        }
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens"
        }
    }

    struct Delta: Decodable {
        var role: String?
        var content: Content?
    }

    struct Choice: Decodable {
        var index: Int?
        var message: Message?
        var delta: Delta?
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message, delta, finishReason = "finish_reason"
        }
    }

    struct Response: Decodable {
        var id: String?
        var model: String?
        var created: Int?
        var choices: [Choice]
        var usage: Usage?
    }

    struct ModelList: Decodable {
        struct Model: Decodable { var id: String }
        var data: [Model]
    }

    static func request(_ request: ChatRequest, preset: Preset, stream: Bool) -> Request {
        Request(model: request.model,
                messages: request.messages.map { Message(role: $0.role.rawValue, content: Content($0.content)) },
                temperature: request.temperature, maxTokens: request.maxTokens, stream: stream,
                extra: preset.extra.merging(request.extra ?? [:]) { _, own in own })
    }

    static func response(_ wire: Response, model: String) throws -> ChatResponse {
        guard let choice = wire.choices.first, let message = choice.message else { throw ProviderError.noChoices }
        let usage = wire.usage.map {
            ChatResponse.Usage(promptTokens: $0.promptTokens ?? 0, completionTokens: $0.completionTokens ?? 0,
                               totalTokens: $0.totalTokens ?? (($0.promptTokens ?? 0) + ($0.completionTokens ?? 0)))
        }
        return ChatResponse(id: wire.id ?? "chat-\(UUID().uuidString.lowercased())", model: wire.model ?? model,
                            message: .assistant(message.content?.text ?? ""),
                            finishReason: choice.finishReason.map(FinishReason.init(wire:)), usage: usage,
                            created: wire.created.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    static func delta(_ wire: Response) -> ChatDelta {
        let choice = wire.choices.first
        return ChatDelta(role: choice?.delta?.role.flatMap(ChatRole.init(rawValue:)),
                         content: choice?.delta?.content?.text,
                         finishReason: choice?.finishReason.map(FinishReason.init(wire:)),
                         id: wire.id, model: wire.model)
    }
}
