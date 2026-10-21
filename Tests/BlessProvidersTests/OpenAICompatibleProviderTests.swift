//
//  OpenAICompatibleProviderTests.swift
//  BlessProvidersTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The client against a stubbed server: where it posts, what it sends, how it reads a
//        whole reply and a stream, and what an HTTP error carries. Serialized: the stub is shared.
//

import Bless
import Foundation
import Testing
@testable import BlessProviders

@Suite("OpenAI-compatible provider", .serialized)
struct OpenAICompatibleProviderTests {
    let request = ChatRequest(model: "mistral-small-latest", messages: [.user("How should I take it?")])

    @Test("complete posts to the preset's URL with the bearer key and returns the message")
    func complete() async throws {
        let body = #"{"id":"cmpl-9","model":"mistral-small-2506","choices":[{"message":{"role":"assistant","content":"With food."},"finish_reason":"stop"}]}"#
        let session = StubProtocol.session(answering: .init(status: 200, body: Data(body.utf8)))
        let provider = OpenAICompatibleProvider(preset: .mistral, apiKey: "test-key", session: session)
        let response = try await provider.complete(request)
        #expect(response.message.content == "With food.")
        #expect(response.id == "cmpl-9")
        let sent = try #require(StubProtocol.lastRequest)
        #expect(sent.url?.absoluteString == "https://api.mistral.ai/v1/chat/completions")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(StubProtocol.lastBody["stream"] as? Bool == false)
    }

    @Test("an HTTP error throws its status and the start of its body")
    func httpError() async throws {
        let session = StubProtocol.session(answering: .init(status: 401, body: Data(#"{"message":"Unauthorized"}"#.utf8)))
        let provider = OpenAICompatibleProvider(preset: .mistral, apiKey: "bad", session: session)
        await #expect(throws: ProviderError.http(status: 401, body: #"{"message":"Unauthorized"}"#)) { try await provider.complete(request) }
        await #expect(throws: ProviderError.http(status: 401, body: #"{"message":"Unauthorized"}"#)) {
            for try await _ in provider.stream(request) {}
        }
    }

    @Test("a missing key is refused before any request when the preset needs one")
    func missingKey() async throws {
        let session = StubProtocol.session(answering: .init(status: 200, body: Data()))
        await #expect(throws: ProviderError.missingAPIKey) {
            try await OpenAICompatibleProvider(preset: .mistral, apiKey: nil, session: session).complete(request)
        }
        #expect(StubProtocol.lastRequest == nil)
    }

    @Test("stream yields deltas from an SSE body until [DONE]")
    func stream() async throws {
        let sse = """
        data: {"id":"c-1","model":"m","choices":[{"delta":{"role":"assistant","content":"With "}}]}

        : comment

        data: {"id":"c-1","model":"m","choices":[{"delta":{"content":"food."},"finish_reason":"stop"}]}

        data: [DONE]

        data: {"choices":[{"delta":{"content":"never read"}}]}

        """
        let session = StubProtocol.session(answering: .init(status: 200, body: Data(sse.utf8), contentType: "text/event-stream"))
        let provider = OpenAICompatibleProvider(preset: .mistral, apiKey: "k", session: session)
        let assembled = try await provider.stream(request).assembled(model: "fallback")
        #expect(assembled.message.content == "With food.")
        #expect(assembled.finishReason == .stop)
        #expect(assembled.id == "c-1")
        #expect(StubProtocol.lastBody["stream"] as? Bool == true)
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test("models lists the ids the key can use")
    func models() async throws {
        let session = StubProtocol.session(answering: .init(status: 200, body: Data(#"{"object":"list","data":[{"id":"mistral-small-latest"},{"id":"mistral-large-latest"}]}"#.utf8)))
        let ids = try await OpenAICompatibleProvider(preset: .mistral, apiKey: "k", session: session).models()
        #expect(ids == ["mistral-small-latest", "mistral-large-latest"])
        #expect(StubProtocol.lastRequest?.url?.absoluteString == "https://api.mistral.ai/v1/models")
    }

    @Test("the presets name their endpoints; Sewn's carries its required object and needs no key")
    func presets() {
        #expect(Preset.openAI.completionsURL.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(Preset.mistral.modelsURL.absoluteString == "https://api.mistral.ai/v1/models")
        let sewn = Preset.sewn(sewn: ["owner_id": "ada"])
        #expect(sewn.completionsURL.absoluteString == "http://127.0.0.1:47080/v1/chat/completions")
        #expect(!sewn.requiresKey)
        #expect(sewn.extra["sewn"] == ["owner_id": "ada"])
    }

    @Test("Blessed wraps the real client exactly as it wraps any provider")
    func blessedClient() async throws {
        let body = #"{"id":"cmpl-9","model":"m","choices":[{"message":{"role":"assistant","content":"With food."},"finish_reason":"stop"}]}"#
        let session = StubProtocol.session(answering: .init(status: 200, body: Data(body.utf8)))
        let doctor = ReviewerIdentity(id: "dr-1", displayName: "Dr. One")
        let gate = Gate()
        let blessed = Blessed(upstream: OpenAICompatibleProvider(preset: .mistral, apiKey: "k", session: session), gate: gate) { _ in
            Routing(conversationID: "v-1", recipient: Party(id: "ada", displayName: "Ada"), reviewers: [doctor.party])
        }
        let reviewer = Task {
            for _ in 0..<5000 {
                if let petition = try await gate.pending().first {
                    try await gate.decide(petition.id, .amend(content: "With food, twice a day."), as: doctor)
                    return
                }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        let response = try await blessed.complete(request)
        try await reviewer.value
        #expect(response.message.content == "With food, twice a day.")
        #expect(blessed.name == "blessed(mistral)")
    }
}
