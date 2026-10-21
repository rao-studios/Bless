//
//  WireTests.swift
//  BlessProvidersTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The chat-completions wire: requests in OpenAI's shape with extra fields at the top
//        level, responses and stream chunks read into Bless's neutral types.
//

import Bless
import Foundation
import Testing
@testable import BlessProviders

@Suite("Wire")
struct WireTests {
    func encoded(_ request: Wire.Request) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("a request encodes to OpenAI's shape with snake_case keys and extra fields at the top level")
    func request() throws {
        let chat = ChatRequest(model: "mistral-small-latest", messages: [.system("Be brief."), .user("Hi")], temperature: 0.2,
                               maxTokens: 300, extra: ["safe_prompt": true])
        let json = try encoded(Wire.request(chat, preset: .mistral, stream: true))
        #expect(json["model"] as? String == "mistral-small-latest")
        #expect(json["max_tokens"] as? Int == 300)
        #expect(json["stream"] as? Bool == true)
        #expect(json["safe_prompt"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        #expect(messages.map { $0["content"] as? String } == ["Be brief.", "Hi"])
    }

    @Test("a request's own extra wins over the preset's, and never over a standard field")
    func extraPrecedence() throws {
        let preset = Preset.sewn(sewn: ["owner_id": "ada", "scope": "visit"])
        let chat = ChatRequest(model: "local", messages: [.user("Hi")], extra: ["sewn": ["owner_id": "bea"], "model": "evil"])
        let json = try encoded(Wire.request(chat, preset: preset, stream: false))
        #expect((json["sewn"] as? [String: Any])?["owner_id"] as? String == "bea")
        #expect(json["model"] as? String == "local")
        let plain = try encoded(Wire.request(ChatRequest(model: "local", messages: [.user("Hi")]), preset: preset, stream: false))
        #expect((plain["sewn"] as? [String: Any])?["scope"] as? String == "visit")
    }

    @Test("a response decodes to a ChatResponse; an unknown finish reason reads as other")
    func response() throws {
        let body = #"{"id":"cmpl-1","model":"mistral-small-2506","created":1760961600,"choices":[{"index":0,"message":{"role":"assistant","content":"Rest.","refusal":null},"finish_reason":"model_length"}],"usage":{"prompt_tokens":12,"completion_tokens":2,"total_tokens":14}}"#
        let response = try Wire.response(try JSONDecoder().decode(Wire.Response.self, from: Data(body.utf8)), model: "fallback")
        #expect(response.id == "cmpl-1")
        #expect(response.model == "mistral-small-2506")
        #expect(response.message == .assistant("Rest."))
        #expect(response.finishReason == .other)
        #expect(response.usage == .init(promptTokens: 12, completionTokens: 2, totalTokens: 14))
        #expect(response.created == Date(timeIntervalSince1970: 1_760_961_600))
    }

    @Test("content given as typed parts is read from its text parts")
    func parts() throws {
        let body = #"{"choices":[{"message":{"role":"assistant","content":[{"type":"thinking","thinking":[]},{"type":"text","text":"Rest "},{"type":"text","text":"well."}]},"finish_reason":"stop"}]}"#
        let response = try Wire.response(try JSONDecoder().decode(Wire.Response.self, from: Data(body.utf8)), model: "m")
        #expect(response.message.content == "Rest well.")
        #expect(response.model == "m")
    }

    @Test("a stream chunk decodes to a delta")
    func chunk() throws {
        let body = #"{"id":"c-1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","content":"Re"},"finish_reason":null}]}"#
        let delta = Wire.delta(try JSONDecoder().decode(Wire.Response.self, from: Data(body.utf8)))
        #expect(delta == ChatDelta(role: .assistant, content: "Re", id: "c-1", model: "m"))
    }

    @Test("no choices is an error")
    func noChoices() throws {
        let wire = try JSONDecoder().decode(Wire.Response.self, from: Data(#"{"choices":[]}"#.utf8))
        #expect(throws: ProviderError.noChoices) { try Wire.response(wire, model: "m") }
    }
}
