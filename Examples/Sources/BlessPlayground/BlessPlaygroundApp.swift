//
//  BlessPlaygroundApp.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The Mac app: one window with the patient, the model and the reviewer side by side over
//        the ledger, all at one Gate. The Petition menu rules on the selected petition from the
//        keyboard. `--snapshot <screen> --out <png>` draws the window off screen instead
//        (Snapshot.swift).
//  PIN:  Runs from SwiftPM with no app bundle (its Info.plist is linked into the binary), so it
//        sets its own activation policy at launch; without it the window would open behind others
//        and never take keyboard focus (Leviathan's PIN, the same recipe).
//

import AppKit
import BlessPlaygroundKit
import SwiftUI

@main
enum Main {
    static func main() {
        if let request = SnapshotRequest(arguments: CommandLine.arguments) {
            MainActor.assumeIsolated { Snapshot.run(request) }
        }
        BlessPlaygroundApp.main()
    }
}

struct BlessPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var session = Session(launch: LaunchOptions(arguments: CommandLine.arguments))
    @State private var reviewer = ReviewerFocus()

    var body: some Scene {
        WindowGroup("Bless Playground") {
            RootView()
                .environment(session)
                .environment(reviewer)
                .task { await session.start() }
        }
        .defaultSize(width: 1480, height: 920)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Visit") { session.newVisit() }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(session.turn != .idle)
            }
            CommandMenu("Petition") {
                Button("Bless") { reviewer.request(.bless) }
                    .keyboardShortcut("b", modifiers: [.command])
                Button("Amend and Release") { reviewer.request(.amend) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Withhold") { reviewer.request(.withhold) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Divider()
                Button("Verify Ledger") { session.verifyLedger() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The menu's ruling, handed to the Reviewer pane, which knows the selection and the edited text.
@MainActor
@Observable
final class ReviewerFocus {
    enum Action { case bless, amend, withhold }
    var requested: (action: Action, at: Date)?

    func request(_ action: Action) { requested = (action, Date()) }
}

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var showsLedger = true

    var body: some View {
        VSplitView {
            HSplitView {
                PatientPane().frame(minWidth: 320, maxWidth: 460)
                ModelPane().frame(minWidth: 320, maxWidth: 420)
                ReviewerPane().frame(minWidth: 520, maxWidth: .infinity)
            }
            .frame(minHeight: 520)
            if showsLedger {
                LedgerPane().frame(minHeight: 170, idealHeight: 240, maxHeight: 320)
            }
        }
        .frame(minWidth: 1180, minHeight: 720)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Label("Bless", systemImage: "checkmark.seal")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
            }
            ToolbarItem {
                Button { showsLedger.toggle() } label: {
                    Label(showsLedger ? "Hide Ledger" : "Show Ledger", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }
}
