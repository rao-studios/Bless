//
//  Snapshot.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Draws the window to a PNG and exits, for the README's picture and for checking the
//        layout without a screen:
//          BlessPlayground --snapshot demo|held --out <file.png> [--dark]
//        `demo`: one question amended and released, a second held with the reviewer; `held`: one
//        question held. Both run the offline fake model with a throwaway reviewer key and settings,
//        so nothing on this Mac is read or written but the PNG.
//  PIN:  Leviathan's recipe: the window is never shown. It is drawn off screen with no Dock icon
//        and copied out of its own views, so it needs no screen-recording permission.
//

import AppKit
import Bless
import BlessPlaygroundKit
import SwiftUI

struct SnapshotRequest: Sendable {
    var screen: String
    var out: URL
    var dark: Bool

    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        guard let screen = value("--snapshot"), let out = value("--out") else { return nil }
        self.screen = screen
        self.out = URL(fileURLWithPath: out)
        dark = arguments.contains("--dark")
    }
}

@MainActor
enum Snapshot {
    static let screens = ["demo", "held"]

    static func run(_ request: SnapshotRequest) -> Never {
        guard screens.contains(request.screen) else {
            FileHandle.standardError.write(Data("no screen '\(request.screen)'; screens: \(screens.joined(separator: ", "))\n".utf8))
            exit(64)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bless-snapshot-\(UUID())")
        let defaults = UserDefaults(suiteName: "nyc.rao.bless.playground.snapshot-\(UUID())")!
        let session = Session(keys: KeyResolver(store: MemoryKeyStore(), environment: [:], raoKeysFile: nil),
                              identities: ReviewerIdentityStore(file: folder.appendingPathComponent("reviewer.json")),
                              defaults: defaults, launch: LaunchOptions(arguments: ["--provider", "fake"]), fakeDelay: .zero)
        let size = CGSize(width: 1480, height: 920)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: request.dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        let host = NSHostingView(rootView: RootView().environment(session).environment(ReviewerFocus())
            .frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        Task {
            await session.start()
            await script(request.screen, session)
            for _ in 1...12 {
                try? await Task.sleep(for: .milliseconds(250))
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
            }
            capture(host, size: size, to: request.out)
            try? FileManager.default.removeItem(at: folder)
            exit(0)
        }
        application.run()
        exit(0)
    }

    private static func script(_ screen: String, _ session: Session) async {
        func held() async -> Petition? {
            for _ in 0..<1000 {
                if case .held = session.turn { return session.pending.first }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return nil
        }
        if screen == "demo" {
            session.seed(Scenarios.all[0])
            session.send()
            if let first = await held() {
                await session.view(first.id)
                await session.decide(.amend(content: "Please avoid ibuprofen with lisinopril: together they can strain your kidneys. Take paracetamol instead, and call us if the knee still hurts in a week."),
                                     on: first.id, note: "NSAID with an ACE inhibitor")
            }
            for _ in 0..<1000 where session.turn != .idle { try? await Task.sleep(for: .milliseconds(5)) }
            session.seed(Scenarios.all[2])
        } else {
            session.seed(Scenarios.all[1])
        }
        session.send()
        _ = await held()
        session.verifyLedger()
    }

    private static func capture(_ host: NSView, size: CGSize, to url: URL) {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(70) }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(70) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("could not write \(url.path): \(error)\n".utf8))
            exit(73)
        }
    }
}
