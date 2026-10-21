//
//  PatientPane.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: What the patient sees: their questions, the replies their care team released (each
//        marked as reviewed, amended, or a holding message), and neutral notices when nothing was
//        released. While a reply is held, a capsule says so and counts the wait; Withdraw takes the
//        question back. The composer's menu fills in one of the invented scenarios.
//

import Bless
import BlessPlaygroundKit
import SwiftUI

struct PatientPane: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            PaneHeader(title: "Patient", subtitle: session.patient.displayName, symbol: "person.crop.circle", tint: Palette.patient)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.transcript.isEmpty {
                            Text("Ask a question as the patient. The model drafts a reply, and nothing reaches this side until the reviewer blesses it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        ForEach(session.transcript) { entry in
                            EntryView(entry: entry).id(entry.id)
                        }
                        if case .drafting = session.turn { HeldCapsule(text: "Preparing a reply", since: nil) }
                        if case .held(_, let since) = session.turn { HeldCapsule(text: "Held for review by your care team", since: since) }
                    }
                    .padding(16)
                }
                .onChange(of: session.transcript.count) {
                    if let last = session.transcript.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            composer
        }
    }

    private var composer: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Message your care team", text: $session.composer, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { session.send() }
            HStack {
                Menu {
                    ForEach(Scenarios.all) { scenario in
                        Button(scenario.title) { session.seed(scenario) }
                    }
                } label: {
                    Label("Scenario", systemImage: "text.badge.plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                if session.turn != .idle {
                    Button("Withdraw", role: .destructive) { Task { await session.withdraw() } }
                }
                Button("Send") { session.send() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canSend)
            }
        }
        .padding(12)
    }
}

private struct EntryView: View {
    let entry: Session.Entry

    var body: some View {
        switch entry {
        case .patient(_, let text, let at):
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(text)
                        .padding(10)
                        .background(Palette.patient.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    Text(Format.time(at)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        case .reply(_, let release, let reviewer):
            VStack(alignment: .leading, spacing: 4) {
                Text(release.message.content)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 4) {
                    Image(systemName: release.basis == .lapsed ? "clock" : "checkmark.seal.fill")
                        .foregroundStyle(release.basis == .lapsed ? Palette.withheld : Palette.reviewer)
                    Text(Format.basis(release.basis, reviewer: reviewer))
                    Text("· \(Format.time(release.released))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.trailing, 40)
        case .notice(_, let text, _):
            Label(text, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        }
    }
}

private struct HeldCapsule: View {
    let text: String
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(text)
                if let since { Text(Format.elapsed(from: since, to: context.date)).monospacedDigit() }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.reviewer.opacity(0.15), in: Capsule())
        }
    }
}
