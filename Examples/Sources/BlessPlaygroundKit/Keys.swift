//
//  Keys.swift
//  BlessPlaygroundKit
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where the playground finds a Mistral key, in order: the Keychain item it saves itself
//        (service nyc.rao.bless.playground, account MISTRAL_API_KEY), the MISTRAL_API_KEY
//        environment variable, then ~/.rao/keys/providers.json (Ambient's store on this Mac). The
//        last two are read, never written; "Forget" removes only the app's own item, so the next
//        source shows through.
//  PIN:  Leviathan's recipe: the item is written and read through /usr/bin/security, so it trusts
//        that tool rather than this binary's changing ad-hoc signature, and survives rebuilds. The
//        key reaches `security` on stdin as hex, never in arguments, so it is not in the process
//        list. A Secret prints as Secret(••••): nothing the app logs or shows contains the key.
//        Every call spawns a process, so the session calls these off the main actor.
//

import Foundation
import Synchronization

/// An API key that never prints.
public struct Secret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: String

    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }

    public var description: String { "Secret(••••)" }
    public var debugDescription: String { "Secret(••••)" }
}

/// Where a key came from.
public enum KeySource: Sendable, Equatable {
    case keychain
    case environment
    case raoKeys(writtenBy: String?)

    public var label: String {
        switch self {
        case .keychain: "this app's Keychain item"
        case .environment: "MISTRAL_API_KEY in the environment"
        case .raoKeys(let writer): "~/.rao/keys" + (writer.map { " (written by \($0))" } ?? "")
        }
    }
}

public struct ResolvedKey: Sendable, Equatable {
    public let secret: Secret
    public let source: KeySource

    public init(secret: Secret, source: KeySource) {
        self.secret = secret
        self.source = source
    }
}

public enum KeyStoreError: Error, Equatable, CustomStringConvertible {
    case toolUnavailable
    case notSaved(hint: String?)
    case notRemoved(hint: String?)

    public var description: String {
        switch self {
        case .toolUnavailable: "/usr/bin/security could not be run"
        case .notSaved(let hint): "the key was not saved to the Keychain" + (hint.map { ": \($0)" } ?? "")
        case .notRemoved(let hint): "the key was not removed from the Keychain" + (hint.map { ": \($0)" } ?? "")
        }
    }
}

public protocol KeyStore: Sendable {
    func read() throws -> Secret?
    func write(_ secret: Secret) throws
    func forget() throws
}

public struct KeychainKeyStore: KeyStore {
    public static let service = "nyc.rao.bless.playground"
    public static let account = "MISTRAL_API_KEY"

    public init() {}

    public func read() throws -> Secret? {
        let found = Self.run(["find-generic-password", "-s", Self.service, "-a", Self.account, "-w"])
        if found.status == -1 { throw KeyStoreError.toolUnavailable }
        guard found.status == 0 else { return nil }  // 44: no such item
        return Secret(String(decoding: found.output, as: UTF8.self))
    }

    public func write(_ secret: Secret) throws {
        let saved = Self.run(["-i"], input: Data(Self.addCommand(service: Self.service, account: Self.account, secret: secret).utf8))
        if saved.status == -1 { throw KeyStoreError.toolUnavailable }
        // `security -i` exits 0 even when a command inside it fails: confirm by reading back.
        guard saved.status == 0, try read() == secret else { throw KeyStoreError.notSaved(hint: Self.clip(saved.error)) }
    }

    public func forget() throws {
        let removed = Self.run(["delete-generic-password", "-s", Self.service, "-a", Self.account])
        guard removed.status == 0 || removed.status == 44 else { throw KeyStoreError.notRemoved(hint: Self.clip(removed.error)) }
    }

    /// The line `security -i` reads: the secret as hex, so no quoting can break it.
    static func addCommand(service: String, account: String, secret: Secret) -> String {
        let hex = Data(secret.value.utf8).map { String(format: "%02x", $0) }.joined()
        return "add-generic-password -U -s \(service) -a \(account) -l \(service).\(account) -X \(hex)\n"
    }

    static func run(_ arguments: [String], input: Data? = nil) -> (status: Int32, output: Data, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe(), error = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = stdin
        do { try process.run() } catch { return (-1, Data(), "\(error)") }
        if let input { stdin.fileHandleForWriting.write(input) }
        try? stdin.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, out, String(decoding: err, as: UTF8.self))
    }

    static func clip(_ text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : String(line.prefix(200))
    }
}

/// A key store in memory, for tests.
public final class MemoryKeyStore: KeyStore {
    private let secret: Mutex<Secret?>

    public init(_ secret: Secret? = nil) { self.secret = Mutex(secret) }

    public func read() throws -> Secret? { secret.withLock { $0 } }
    public func write(_ value: Secret) throws { secret.withLock { $0 = value } }
    public func forget() throws { secret.withLock { $0 = nil } }
}

public struct KeyResolver: Sendable {
    public let store: any KeyStore
    public let environment: [String: String]
    public let raoKeysFile: URL?

    public init(store: any KeyStore, environment: [String: String], raoKeysFile: URL?) {
        self.store = store
        self.environment = environment
        self.raoKeysFile = raoKeysFile
    }

    /// The Keychain, this process's environment, and this Mac's ~/.rao/keys/providers.json.
    public static func live() -> KeyResolver {
        KeyResolver(store: KeychainKeyStore(), environment: ProcessInfo.processInfo.environment,
                    raoKeysFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".rao/keys/providers.json"))
    }

    /// The first key found, and where.
    public func resolve() -> ResolvedKey? {
        if let secret = try? store.read() { return ResolvedKey(secret: secret, source: .keychain) }
        if let secret = environment["MISTRAL_API_KEY"].flatMap(Secret.init) { return ResolvedKey(secret: secret, source: .environment) }
        if let file = raoKeysFile, let data = try? Data(contentsOf: file),
           let records = try? JSONDecoder().decode([String: RaoKey].self, from: data),
           let record = records["MISTRAL_API_KEY"], let secret = Secret(record.value) {
            return ResolvedKey(secret: secret, source: .raoKeys(writtenBy: record.writtenBy))
        }
        return nil
    }

    /// One record of ~/.rao/keys/providers.json (only these fields are read).
    struct RaoKey: Decodable {
        var value: String
        var writtenBy: String?
    }
}
