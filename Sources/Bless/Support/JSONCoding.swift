//
//  JSONCoding.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The JSON every Bless store and export writes: keys sorted, dates as whole milliseconds
//        since 1970 (integers), data as base64. Read it back with `decoder()`.
//  PIN:  Integer milliseconds, not ISO 8601: Foundation's ISO 8601 drops fractional seconds,
//        and a verdict whose `issued` moved by a millisecond would no longer verify.
//

import Foundation

public enum JSONCoding {
    /// Sorted keys, integer-millisecond dates, compact.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Canonical.milliseconds(date))
        }
        return encoder
    }

    /// The same, indented, for files a person reads.
    public static func prettyEncoder() -> JSONEncoder {
        let encoder = encoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return encoder
    }

    /// Reads what `encoder()` writes.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Canonical.date(milliseconds: try container.decode(Int64.self))
        }
        return decoder
    }
}
