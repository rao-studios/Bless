//
//  SSETests.swift
//  BlessProvidersTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Server-sent events read byte by byte: blank lines end events, comments and other
//        fields are skipped, CRLF reads as LF, multi-line data joins with newlines.
//

import Foundation
import Testing
@testable import BlessProviders

@Suite("Server-sent events")
struct SSETests {
    func events(_ text: String) -> [String] {
        var parser = SSEParser()
        var out: [String] = []
        for byte in Array(text.utf8) {
            if let event = parser.feed(byte) { out.append(event) }
        }
        if let event = parser.finish() { out.append(event) }
        return out
    }

    @Test("events split on blank lines; comments and other fields are ignored")
    func split() {
        #expect(events(": keep-alive\ndata: {\"a\":1}\n\nevent: x\nid: 7\ndata: [DONE]\n\n") == ["{\"a\":1}", "[DONE]"])
    }

    @Test("multi-line data joins with a newline; a space after the colon is optional")
    func multiline() {
        #expect(events("data: one\ndata:two\n\n") == ["one\ntwo"])
    }

    @Test("CRLF line endings read as LF, and an event open at the end is delivered")
    func crlf() {
        #expect(events("data: a\r\n\r\ndata: b") == ["a", "b"])
    }
}
