//
//  SSE.swift
//  BlessProviders
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Server-sent events, byte by byte: `data:` lines are gathered until a blank line ends the
//        event, comment lines (`:`) and other fields are ignored, CRLF is read as LF, and an
//        event still open when the stream ends is delivered. The chat stream ends at `[DONE]`.
//  PIN:  Fed bytes, not lines: Foundation's async `lines` drops blank lines, and the blank line
//        is what ends an event (checked on this Mac, 2026-10-20).
//

import Foundation

struct SSEParser {
    private var line: [UInt8] = []
    private var data: [String] = []

    /// Feeds one byte; returns an event's data when this byte completes one.
    mutating func feed(_ byte: UInt8) -> String? {
        guard byte == 0x0A else {
            line.append(byte)
            return nil
        }
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        return take(line)
    }

    /// The event still open at the end of the stream, if any.
    mutating func finish() -> String? {
        if !line.isEmpty {
            if let event = take(line) { return event }
            line.removeAll()
        }
        return flush()
    }

    private mutating func take(_ line: [UInt8]) -> String? {
        if line.isEmpty { return flush() }
        if line.first == 0x3A { return nil }  // ":" comment
        let text = String(decoding: line, as: UTF8.self)
        guard text.hasPrefix("data:") else { return nil }
        var value = text.dropFirst(5)
        if value.first == " " { value = value.dropFirst() }
        data.append(String(value))
        return nil
    }

    private mutating func flush() -> String? {
        guard !data.isEmpty else { return nil }
        defer { data.removeAll() }
        return data.joined(separator: "\n")
    }
}
