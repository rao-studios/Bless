//
//  Stub.swift
//  BlessProvidersTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: A URLProtocol that answers the provider's requests from the test, on an ephemeral
//        session, and keeps each request (body included) for the test to read. No network.
//

import Foundation
import Synchronization

final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: Data
        var contentType = "application/json"
    }

    static let reply = Mutex<Reply>(Reply(status: 200, body: Data()))
    static let seen = Mutex<[URLRequest]>([])

    static func session(answering reply: Reply) -> URLSession {
        self.reply.withLock { $0 = reply }
        seen.withLock { $0.removeAll() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    static var lastRequest: URLRequest? { seen.withLock { $0.last } }

    static var lastBody: [String: Any] {
        guard let body = lastRequest?.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return object
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        Self.seen.withLock { $0.append(request) }
        let reply = Self.reply.withLock { $0 }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": reply.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
