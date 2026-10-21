//
//  OpenAICompatibleProvider.swift
//  BlessProviders
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: An InferenceProvider for any layer that speaks the chat-completions wire: POST
//        `<base>/chat/completions` with a bearer key, whole (`complete`) or as server-sent
//        events (`stream`), plus `models()` to list what the key can use (the playground's
//        key check). Errors keep the HTTP status and the start of the body, never the key.
//

import Bless
import Foundation

public enum ProviderError: Error, Equatable, CustomStringConvertible {
    case missingAPIKey
    case http(status: Int, body: String)
    case decoding(String)
    case noChoices

    public var description: String {
        switch self {
        case .missingAPIKey: "this provider needs an API key"
        case .http(let status, let body): "HTTP \(status)\(body.isEmpty ? "" : ": \(body)")"
        case .decoding(let why): "the reply did not decode: \(why)"
        case .noChoices: "the reply had no choices"
        }
    }
}

public struct OpenAICompatibleProvider: InferenceProvider {
    public let preset: Preset
    private let apiKey: String?
    private let session: URLSession

    public init(preset: Preset, apiKey: String?, session: URLSession = .shared) {
        self.preset = preset
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
    }

    public var name: String { preset.name }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let (data, response) = try await session.data(for: try urlRequest(request, stream: false))
        try check(response, body: data)
        do {
            return try Wire.response(try JSONDecoder().decode(Wire.Response.self, from: data), model: request.model)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.decoding(String(describing: error).prefix(200).description)
        }
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: try urlRequest(request, stream: true))
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 2048 { break }
                        }
                        try check(response, body: body)
                    }
                    var parser = SSEParser()
                    let decoder = JSONDecoder()
                    func deliver(_ event: String) throws -> Bool {
                        if event == "[DONE]" { return false }
                        do {
                            continuation.yield(Wire.delta(try decoder.decode(Wire.Response.self, from: Data(event.utf8))))
                        } catch {
                            throw ProviderError.decoding("a stream event: \(event.prefix(120))")
                        }
                        return true
                    }
                    reading: for try await byte in bytes {
                        if let event = parser.feed(byte), try !deliver(event) { break reading }
                    }
                    if let event = parser.finish() { _ = try deliver(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The ids of the models this key can use (`GET <base>/models`).
    public func models() async throws -> [String] {
        var request = URLRequest(url: preset.modelsURL)
        try authorize(&request)
        let (data, response) = try await session.data(for: request)
        try check(response, body: data)
        do {
            return try JSONDecoder().decode(Wire.ModelList.self, from: data).data.map(\.id)
        } catch {
            throw ProviderError.decoding("the model list")
        }
    }

    private func urlRequest(_ request: ChatRequest, stream: Bool) throws -> URLRequest {
        var out = URLRequest(url: preset.completionsURL)
        out.httpMethod = "POST"
        out.setValue("application/json", forHTTPHeaderField: "Content-Type")
        out.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        try authorize(&out)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        out.httpBody = try encoder.encode(Wire.request(request, preset: preset, stream: stream))
        return out
    }

    private func authorize(_ request: inout URLRequest) throws {
        for (field, value) in preset.headers { request.setValue(value, forHTTPHeaderField: field) }
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else if preset.requiresKey {
            throw ProviderError.missingAPIKey
        }
    }

    private func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let text = String(decoding: body.prefix(600), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ProviderError.http(status: http.statusCode, body: text)
    }
}
