//
//  PackageLayeringTests.swift
//  BlessTests
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The package's rules, as text over Package.swift, Sources/, Tests/ and Examples/:
//        exactly two library products and no executable; the layer table; the core on Foundation,
//        CryptoKit and Synchronization alone, CryptoKit in four named files; no UI, logging or
//        print anywhere in Sources/; the ledger never reads a message's content; no type named
//        like a module; nothing left of the multi-party brainstorm; every Swift file opens with
//        its name, target, author, copyright and WHAT, and every manifest with its author and
//        copyright; every script and site file names the GPL-3.0; the playground's kit has no UI;
//        the local-only paths are ignored.
//

import Foundation
import Testing

private let repoRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    while url.lastPathComponent != "Tests" { url.deleteLastPathComponent() }
    return url.deletingLastPathComponent()
}()

private let license = "SPDX-License-Identifier: GPL-3.0-only"
private let author = "Ritesh Pakala"
private let copyright = "Copyright © 2026 Rao Studios LLC."

private func text(_ relative: String) throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
}

private func exists(_ relative: String) -> Bool {
    FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relative).path)
}

private func files(under relative: String, extensions: Set<String> = ["swift"]) -> [URL] {
    let root = repoRoot.appendingPathComponent(relative)
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    return walker.compactMap { $0 as? URL }
        .filter { extensions.contains($0.pathExtension) && !$0.path.contains("/.build/") && !$0.path.contains("/.swiftpm/") }
        .sorted { $0.path < $1.path }
}

private func imports(in body: String) -> [String] {
    body.split(separator: "\n").compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["@_exported import ", "@testable import ", "import "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count).split(separator: " ").first ?? "")
        }
        return nil
    }
}

private func relative(_ url: URL) -> String {
    url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
}

/// Source lines with comments removed, so a rule about code is not tripped by prose.
private func code(_ body: String) -> String {
    body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { return "" }
        if let range = line.range(of: " // ") { return line[..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

@Suite("Package layering")
struct PackageLayeringTests {
    /// Who may depend on whom. A new edge is a design change: change this table on purpose.
    static let layers: [String: Set<String>] = ["Bless": [], "BlessProviders": ["Bless"]]

    @Test("two library products, Bless and BlessProviders, and no executable")
    func products() throws {
        let manifest = try text("Package.swift")
        #expect(manifest.contains(".library(name: \"Bless\", targets: [\"Bless\"])"))
        #expect(manifest.contains(".library(name: \"BlessProviders\", targets: [\"BlessProviders\"])"))
        #expect(manifest.components(separatedBy: ".library(name:").count == 3)
        #expect(!manifest.contains(".executable"))
        #expect(!manifest.contains(".package(url:") && !manifest.contains(".package(path:"))
    }

    @Test("the platforms are macOS 15 and iOS 18, and no upcoming-feature flags are set")
    func platforms() throws {
        let manifest = try text("Package.swift")
        #expect(manifest.contains("platforms: [.macOS(.v15), .iOS(.v18)]"))
        #expect(!manifest.contains("enableUpcomingFeature"))
    }

    @Test("the source targets and their edges are the layer table")
    func layerTable() throws {
        let manifest = try text("Package.swift")
        #expect(manifest.contains(".target(name: \"Bless\")"))
        #expect(manifest.contains(".target(name: \"BlessProviders\", dependencies: [\"Bless\"])"))
        let targets = try NSRegularExpression(pattern: #"\.target\(name:\s*"(\w+)""#)
        let ns = manifest as NSString
        let names = targets.matches(in: manifest, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        #expect(Set(names) == Set(Self.layers.keys))
    }

    @Test("Bless imports Foundation, CryptoKit and Synchronization only; BlessProviders adds Bless")
    func importsAllowed() throws {
        let allowed: [String: Set<String>] = ["Bless": ["Foundation", "CryptoKit", "Synchronization"],
                                              "BlessProviders": ["Foundation", "Synchronization", "Bless"]]
        for (target, names) in allowed {
            let sources = files(under: "Sources/\(target)")
            #expect(!sources.isEmpty)
            for file in sources {
                for name in imports(in: try String(contentsOf: file, encoding: .utf8)) {
                    #expect(names.contains(name), "\(relative(file)) imports \(name)")
                }
            }
        }
    }

    @Test("CryptoKit is imported in exactly four files")
    func cryptoKitFiles() throws {
        let users = try files(under: "Sources").filter { imports(in: try String(contentsOf: $0, encoding: .utf8)).contains("CryptoKit") }
        #expect(Set(users.map(relative)) == [
            "Sources/Bless/Support/Sha256.swift", "Sources/Bless/Seal/Seal.swift",
            "Sources/Bless/Parties/ReviewerIdentity.swift", "Sources/Bless/Store/StoreCipher.swift",
        ])
    }

    @Test("nothing under Sources imports a UI or logging framework, or prints")
    func noUIOrLogging() throws {
        for file in files(under: "Sources") {
            let body = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["SwiftUI", "AppKit", "UIKit", "os", "OSLog", "Combine", "Logging"] {
                #expect(!imports(in: body).contains(forbidden), "\(relative(file)) imports \(forbidden)")
            }
            #expect(!code(body).contains("print("), "\(relative(file)) prints")
            #expect(!code(body).contains("NSLog("), "\(relative(file)) logs")
        }
    }

    @Test("the ledger never reads a message's content")
    func ledgerHasNoContent() throws {
        let ledger = files(under: "Sources/Bless/Ledger")
        #expect(ledger.count >= 4)
        for file in ledger {
            let body = code(try String(contentsOf: file, encoding: .utf8))
            #expect(!body.contains(".content"), "\(relative(file)) reads .content")
            #expect(!body.contains("reason"), "\(relative(file)) touches a reason")
            #expect(!body.contains("note"), "\(relative(file)) touches a note")
        }
    }

    @Test("no type is named like a module")
    func names() throws {
        let modules: Set<String> = ["Bless", "BlessProviders", "Foundation", "CryptoKit", "Synchronization", "Testing"]
        let declaration = try NSRegularExpression(pattern: #"\b(struct|class|enum|actor|protocol|typealias)\s+(\w+)"#)
        for file in files(under: "Sources") + files(under: "Examples/Sources") {
            let body = code(try String(contentsOf: file, encoding: .utf8))
            let ns = body as NSString
            for match in declaration.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: match.range(at: 2))
                #expect(!modules.contains(name), "\(relative(file)) declares a type named \(name)")
            }
        }
    }

    @Test("nothing is left of the multi-party brainstorm in Sources")
    func noBrainstorm() throws {
        for file in files(under: "Sources") {
            let body = try String(contentsOf: file, encoding: .utf8)
            #expect(!body.contains("MPC"), "\(relative(file)) mentions MPC")
        }
        #expect(!exists("Sources/BlessCLI"))
    }

    @Test("every Swift file opens with its name, its target, its author and copyright, and a WHAT")
    func headers() throws {
        let created = try NSRegularExpression(pattern: #"^//  Created by \#(author) on \d\d/\d\d/\d\d\.$"#)
        for root in ["Sources", "Tests", "Examples/Sources", "Examples/Tests"] {
            let base = root.hasPrefix("Examples/") ? String(root.dropFirst("Examples/".count)) : root
            for file in files(under: root) {
                let body = try String(contentsOf: file, encoding: .utf8)
                let components = file.deletingLastPathComponent().pathComponents
                let target = components.drop { $0 != base }.dropFirst().first ?? ""
                let lines = body.split(separator: "\n", omittingEmptySubsequences: false).prefix(8).map(String.init)
                let named = ["//", "//  \(file.lastPathComponent)", "//  \(target)", "//"]
                let opens = lines.count == 8 && Array(lines[0..<4]) == named
                    && created.firstMatch(in: lines[4], range: NSRange(location: 0, length: (lines[4] as NSString).length)) != nil
                    && lines[5] == "//  \(copyright)" && lines[6] == "//" && lines[7].hasPrefix("//  WHAT:")
                #expect(opens, "\(relative(file)) does not open with its name, target, author, copyright and WHAT")
            }
        }
    }

    @Test("the manifests name their author and copyright; every script and the site's code name the GPL-3.0 at the top")
    func licenses() throws {
        for manifest in ["Package.swift", "Examples/Package.swift"] where exists(manifest) {
            let lines = try text(manifest).split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines.count > 2 && lines[1].hasPrefix("// Created by \(author) on ") && lines[2] == "// \(copyright)",
                    "\(manifest) names its author and copyright after its tools version")
        }
        var scripts: [String] = ["Examples/run.sh"].filter(exists)
        for folder in ["Scripts", "Docs/site/src", "Docs/site/js", "Docs/site/js/figures", "Docs/site/css", "Docs/README_Assets/src"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: repoRoot.appendingPathComponent(folder).path)) ?? []
            scripts += names.filter { !$0.hasPrefix(".") && ["sh", "py", "js", "css", "command"].contains(URL(fileURLWithPath: $0).pathExtension) }
                .map { "\(folder)/\($0)" }
        }
        #expect(scripts.contains("Scripts/test.sh"))
        for script in scripts.sorted() {
            let top = try text(script).split(separator: "\n", omittingEmptySubsequences: false).prefix(16)
            #expect(top.contains { $0.hasSuffix(license) }, "\(script) names its license near the top")
        }
        #expect(try text("LICENSE").hasPrefix("                    GNU GENERAL PUBLIC LICENSE\n                       Version 3, 29 June 2007"))
    }

    @Test("the playground's kit has no UI, and only its app imports SwiftUI or AppKit")
    func playgroundLayers() throws {
        guard exists("Examples/Package.swift") else { return }
        for file in files(under: "Examples/Sources/BlessPlaygroundKit") {
            for name in imports(in: try String(contentsOf: file, encoding: .utf8)) {
                #expect(["Foundation", "Bless", "BlessProviders", "Observation", "Synchronization"].contains(name),
                        "\(relative(file)) imports \(name)")
            }
        }
        for file in files(under: "Examples") where !file.path.contains("/Sources/BlessPlayground/") {
            let names = imports(in: try String(contentsOf: file, encoding: .utf8))
            #expect(!names.contains("SwiftUI") && !names.contains("AppKit"), "\(relative(file)) imports UI")
        }
    }

    @Test("CLAUDE.md, .build, .swiftpm, .claude, .vscode, the three local docs, Docs/examples and the orb's key file are ignored")
    func ignored() throws {
        let ignore = try text(".gitignore").split(separator: "\n").map(String.init)
        for entry in ["CLAUDE.md", ".build", ".swiftpm", ".claude", ".vscode", "ARCHITECTURE.md", "/Docs/examples", "/Docs/EXPLORER.md", "/Docs/EXAMPLES.md", "/Docs/site/local/"] {
            #expect(ignore.contains(entry), ".gitignore lacks \(entry)")
        }
    }
}
