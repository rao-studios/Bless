//
//  Providers.swift
//  BlessPlaygroundKit
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Which model drafts the replies: Mistral (the default, with a key), any OpenAI-compatible
//        layer at a URL (Sewn, Ollama, LM Studio), or the offline fake, which streams a scenario's
//        reply word by word and needs no key and no network. The choice is kept in UserDefaults.
//

import Bless
import BlessProviders
import Foundation

public enum ProviderChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case mistral
    case openAICompatible = "openai-compatible"
    case fake

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mistral: "Mistral"
        case .openAICompatible: "OpenAI-compatible"
        case .fake: "Offline fake"
        }
    }

    public var models: [String] {
        switch self {
        case .mistral: ["mistral-small-latest", "mistral-medium-latest", "mistral-large-latest"]
        case .openAICompatible: ["llama3.2", "qwen2.5", "local"]
        case .fake: [FakeProvider.model]
        }
    }

    public var needsKey: Bool { self == .mistral }
}

public struct ProviderSettings: Codable, Equatable, Sendable {
    public var choice: ProviderChoice
    public var model: String
    public var baseURL: String

    public static let defaultBaseURL = "http://127.0.0.1:11434/v1"

    public init(choice: ProviderChoice = .mistral, model: String = "mistral-small-latest", baseURL: String = ProviderSettings.defaultBaseURL) {
        self.choice = choice
        self.model = model
        self.baseURL = baseURL
    }
}

public enum ProviderSetupError: Error, Equatable, CustomStringConvertible {
    case noKey
    case badURL(String)

    public var description: String {
        switch self {
        case .noKey: "Mistral needs a key: add one under Key…, or choose the offline fake"
        case .badURL(let text): "not a URL: \(text)"
        }
    }
}

/// The model the settings name.
public func makeProvider(_ settings: ProviderSettings, key: Secret?, fakeDelay: Duration = .milliseconds(45)) throws -> any InferenceProvider {
    switch settings.choice {
    case .mistral:
        guard let key else { throw ProviderSetupError.noKey }
        return OpenAICompatibleProvider(preset: .mistral, apiKey: key.value)
    case .openAICompatible:
        guard let url = URL(string: settings.baseURL), url.scheme != nil else { throw ProviderSetupError.badURL(settings.baseURL) }
        return OpenAICompatibleProvider(preset: .custom(name: "openai-compatible", baseURL: url), apiKey: key?.value)
    case .fake:
        return FakeProvider(delay: fakeDelay)
    }
}

/// A model with no network: it streams a scenario's reply a word at a time.
public struct FakeProvider: InferenceProvider {
    public static let model = "fake-clinical-draft"
    public let delay: Duration
    public let name = "fake"

    public init(delay: Duration = .milliseconds(45)) { self.delay = delay }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        try await stream(request).assembled(model: Self.model)
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, any Error> {
        let reply = Scenarios.fakeReply(to: request.messages.last { $0.role == .user }?.content ?? "")
        let delay = self.delay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let id = "fake-\(UUID().uuidString.prefix(8).lowercased())"
                    let words = reply.split(separator: " ", omittingEmptySubsequences: false)
                    for (index, word) in words.enumerated() {
                        if delay > .zero { try await Task.sleep(for: delay) }
                        try Task.checkCancellation()
                        continuation.yield(ChatDelta(role: index == 0 ? .assistant : nil,
                                                     content: index == 0 ? String(word) : " " + word, id: id, model: Self.model))
                    }
                    continuation.yield(ChatDelta(finishReason: .stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
