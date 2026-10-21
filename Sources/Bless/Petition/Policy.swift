//
//  Policy.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The rules one petition is held under: how many reviewers must bless it (quorum), how
//        long they have (deadline) and what happens when it passes (onLapse), whether a reviewer
//        may change the text (allowsAmendment), how much of the conversation the reviewer sees
//        and the store keeps (contextWindow), and whether verdicts must be sealed.
//  PIN:  The defaults are the owner's: one reviewer, no deadline, a lapse holds (nothing
//        unreviewed is ever released by default), amendments allowed, the whole conversation
//        minus system messages, seals required. JSON writes the deadline as whole milliseconds.
//

import Foundation

public struct Policy: Sendable, Equatable {
    /// What happens to a petition still pending at its deadline.
    public enum Lapse: Sendable, Equatable {
        /// Nothing: it stays pending until a reviewer rules. The default.
        case hold
        /// It expires, and nothing is released.
        case withhold
        /// It expires, and this fixed text is released in its place (a safe holding message,
        /// such as "Your care team will reply soon"). Never the model's draft.
        case releaseFallback(String)

        public var name: String {
            switch self {
            case .hold: "hold"
            case .withhold: "withhold"
            case .releaseFallback: "releaseFallback"
            }
        }
    }

    public var quorum: Int
    public var deadline: Duration?
    public var onLapse: Lapse
    public var allowsAmendment: Bool
    /// How many of the latest user and assistant messages the petition keeps; nil keeps them all.
    public var contextWindow: Int?
    public var requiresSeal: Bool

    public init(quorum: Int = 1, deadline: Duration? = nil, onLapse: Lapse = .hold, allowsAmendment: Bool = true,
                contextWindow: Int? = nil, requiresSeal: Bool = true) {
        self.quorum = quorum
        self.deadline = deadline
        self.onLapse = onLapse
        self.allowsAmendment = allowsAmendment
        self.contextWindow = contextWindow
        self.requiresSeal = requiresSeal
    }

    /// Throws `.invalidPolicy` unless these reviewers can meet the policy.
    public func validate(reviewers: [Party]) throws {
        guard !reviewers.isEmpty else { throw BlessError.invalidPolicy("a petition needs at least one reviewer") }
        guard Set(reviewers.map(\.id)).count == reviewers.count else {
            throw BlessError.invalidPolicy("each reviewer may be named once")
        }
        guard quorum >= 1, quorum <= reviewers.count else {
            throw BlessError.invalidPolicy("quorum \(quorum) of \(reviewers.count) reviewers")
        }
        if let deadline, deadline <= .zero { throw BlessError.invalidPolicy("the deadline must be in the future") }
        if let contextWindow, contextWindow < 0 { throw BlessError.invalidPolicy("the context window cannot be negative") }
        if case .releaseFallback(let text) = onLapse, text.isEmpty {
            throw BlessError.invalidPolicy("a fallback release needs its text")
        }
        if requiresSeal {
            for reviewer in reviewers where reviewer.verifyingKey?.count != 32 {
                throw BlessError.sealRequired(reviewer.id)
            }
        }
    }

    /// The conversation as the petition keeps it: no system messages, and only the latest
    /// `contextWindow` of the rest.
    public func trimmed(_ context: [ChatMessage]) -> [ChatMessage] {
        let turns = context.filter { $0.role != .system }
        guard let contextWindow else { return turns }
        return Array(turns.suffix(contextWindow))
    }

    /// The deadline in seconds, as a TimeInterval.
    var deadlineInterval: TimeInterval? {
        deadline.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 }
    }
}

extension Policy: Codable {
    private enum CodingKeys: String, CodingKey {
        case quorum, deadlineMilliseconds, onLapse, fallback, allowsAmendment, contextWindow, requiresSeal
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quorum = try c.decode(Int.self, forKey: .quorum)
        deadline = try c.decodeIfPresent(Int64.self, forKey: .deadlineMilliseconds).map { .milliseconds($0) }
        switch try c.decode(String.self, forKey: .onLapse) {
        case "hold": onLapse = .hold
        case "withhold": onLapse = .withhold
        case "releaseFallback": onLapse = .releaseFallback(try c.decode(String.self, forKey: .fallback))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .onLapse, in: c, debugDescription: "unknown lapse \(other)")
        }
        allowsAmendment = try c.decode(Bool.self, forKey: .allowsAmendment)
        contextWindow = try c.decodeIfPresent(Int.self, forKey: .contextWindow)
        requiresSeal = try c.decode(Bool.self, forKey: .requiresSeal)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(quorum, forKey: .quorum)
        if let deadline {
            let ms = deadline.components.seconds * 1000 + deadline.components.attoseconds / 1_000_000_000_000_000
            try c.encode(ms, forKey: .deadlineMilliseconds)
        }
        try c.encode(onLapse.name, forKey: .onLapse)
        if case .releaseFallback(let text) = onLapse { try c.encode(text, forKey: .fallback) }
        try c.encode(allowsAmendment, forKey: .allowsAmendment)
        try c.encodeIfPresent(contextWindow, forKey: .contextWindow)
        try c.encode(requiresSeal, forKey: .requiresSeal)
    }
}
