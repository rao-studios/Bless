//
//  Preset.swift
//  BlessProviders
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where an OpenAI-compatible layer lives and what it needs: its base URL, the paths of
//        its chat-completions and model-list endpoints, any fixed headers, and top-level fields
//        every request must carry. OpenAI, Mistral and AII's Sewn are named; `custom` covers
//        the rest (vLLM, Ollama, LM Studio, a hospital's own gateway).
//  PIN:  Sewn's /v1/chat/completions is OpenAI-shaped but requires a `sewn` object (owner and
//        scope); it rides in `extra`, and a request's own `extra` wins per key. Sewn listens on
//        loopback 47080 (AII's README).
//

import Bless
import Foundation

public struct Preset: Sendable, Equatable {
    public var name: String
    public var baseURL: URL
    public var completionsPath: String
    public var modelsPath: String
    public var headers: [String: String]
    public var extra: [String: JSONValue]
    /// Whether requests need a bearer key.
    public var requiresKey: Bool

    public init(name: String, baseURL: URL, completionsPath: String = "chat/completions", modelsPath: String = "models",
                headers: [String: String] = [:], extra: [String: JSONValue] = [:], requiresKey: Bool = true) {
        self.name = name
        self.baseURL = baseURL
        self.completionsPath = completionsPath
        self.modelsPath = modelsPath
        self.headers = headers
        self.extra = extra
        self.requiresKey = requiresKey
    }

    public static let openAI = Preset(name: "openai", baseURL: URL(string: "https://api.openai.com/v1")!)

    public static let mistral = Preset(name: "mistral", baseURL: URL(string: "https://api.mistral.ai/v1")!)

    /// AII's Sewn on this Mac, with the `sewn` object its chat route requires.
    public static func sewn(baseURL: URL = URL(string: "http://127.0.0.1:47080/v1")!,
                            sewn: [String: JSONValue]) -> Preset {
        Preset(name: "sewn", baseURL: baseURL, extra: ["sewn": .object(sewn)], requiresKey: false)
    }

    /// Any other layer that speaks the same wire.
    public static func custom(name: String, baseURL: URL, requiresKey: Bool = false) -> Preset {
        Preset(name: name, baseURL: baseURL, requiresKey: requiresKey)
    }

    var completionsURL: URL { baseURL.appending(path: completionsPath) }
    var modelsURL: URL { baseURL.appending(path: modelsPath) }
}
