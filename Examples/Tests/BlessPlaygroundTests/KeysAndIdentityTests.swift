//
//  KeysAndIdentityTests.swift
//  BlessPlaygroundTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where the key comes from (the app's item, then the environment, then ~/.rao/keys), that
//        a key never prints, and that the reviewer's identity is kept privately and survives a
//        relaunch. No real Keychain item is touched.
//

import Bless
import BlessPlaygroundKit
import Foundation
import Testing

@Suite("Keys and identity")
struct KeysAndIdentityTests {
    func raoKeys(_ value: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bless-rao-\(UUID()).json")
        try Data(#"{"MISTRAL_API_KEY":{"value":"\#(value)","source":"test","writtenBy":"ambient","updatedAt":"2026-10-20"}}"#.utf8).write(to: url)
        return url
    }

    @Test("the app's own item wins, then the environment, then ~/.rao/keys")
    func precedence() throws {
        let file = try raoKeys("from-rao")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = MemoryKeyStore(Secret("from-keychain"))
        let all = KeyResolver(store: store, environment: ["MISTRAL_API_KEY": "from-env"], raoKeysFile: file)
        #expect(all.resolve() == ResolvedKey(secret: Secret("from-keychain")!, source: .keychain))
        try store.forget()
        #expect(all.resolve()?.source == .environment)
        let noEnv = KeyResolver(store: store, environment: ["MISTRAL_API_KEY": "  "], raoKeysFile: file)
        #expect(noEnv.resolve() == ResolvedKey(secret: Secret("from-rao")!, source: .raoKeys(writtenBy: "ambient")))
        #expect(KeyResolver(store: store, environment: [:], raoKeysFile: nil).resolve() == nil)
    }

    @Test("a secret never prints, and an empty one is no secret")
    func redacted() throws {
        let secret = try #require(Secret("sk-very-secret"))
        #expect("\(secret)" == "Secret(••••)")
        #expect(String(reflecting: secret) == "Secret(••••)")
        #expect(Secret("   ") == nil)
    }

    @Test("the reviewer's identity is kept 0600 and comes back with the same key")
    func identity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bless-identity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ReviewerIdentityStore(file: folder.appendingPathComponent("reviewer.json"))
        let first = try store.loadOrCreate()
        let again = try store.loadOrCreate()
        #expect(again.verifyingKey == first.verifyingKey)
        let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let renamed = try store.rename(first, to: "Dr. Shah")
        #expect(renamed.verifyingKey == first.verifyingKey && renamed.party.displayName == "Dr. Shah")
        let fresh = try store.regenerate(displayName: "Dr. Shah")
        #expect(fresh.fingerprint != first.fingerprint)
        #expect(try store.loadOrCreate().fingerprint == fresh.fingerprint)
    }

    @Test("launch flags pick the provider, the model and a scenario; unknown ones are ignored")
    func launch() {
        let options = LaunchOptions(arguments: ["BlessPlayground", "-NSDocumentRevisionsDebugMode", "YES", "--provider", "mistral",
                                                "--model", "mistral-large-latest", "--scenario", "fever"])
        #expect(options.provider == .mistral)
        #expect(options.model == "mistral-large-latest")
        #expect(options.scenario?.id == "fever")
        #expect(LaunchOptions(arguments: ["--provider", "nope"]).provider == nil)
    }

    @Test("the offline fake streams a scenario's reply word by word")
    func fake() async throws {
        let request = ChatRequest(model: FakeProvider.model, messages: [.user(Scenarios.all[2].question)])
        var pieces = 0
        var text = ""
        for try await delta in FakeProvider(delay: .zero).stream(request) {
            if let content = delta.content { pieces += 1; text += content }
        }
        #expect(text == Scenarios.all[2].fakeReply)
        #expect(pieces == Scenarios.all[2].fakeReply.split(separator: " ").count)
    }
}
