//
//  Ruling.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: What a reviewer decides about a held reply: bless it as written, amend it (the amended
//        text is what the recipient gets), or withhold it (nothing is sent; the reason stays in
//        the petition store for the host's records, never in the ledger).
//

import Foundation

public enum Ruling: Sendable, Equatable {
    case bless
    case amend(content: String)
    case withhold(reason: String)

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case bless, amend, withhold
    }

    public var kind: Kind {
        switch self {
        case .bless: .bless
        case .amend: .amend
        case .withhold: .withhold
        }
    }
}

extension Ruling: Codable {
    private enum CodingKeys: String, CodingKey { case kind, content, reason }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .bless: self = .bless
        case .amend: self = .amend(content: try c.decode(String.self, forKey: .content))
        case .withhold: self = .withhold(reason: try c.decode(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .bless: break
        case .amend(let content): try c.encode(content, forKey: .content)
        case .withhold(let reason): try c.encode(reason, forKey: .reason)
        }
    }
}
