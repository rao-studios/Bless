//
//  ReviewerPane.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The reviewer's desk: the queue of held replies with their countdowns, the selected
//        petition's conversation (only what the policy lets a reviewer see), the draft in an editor,
//        and three rulings: Bless (as written), Amend and release (the edited text), Withhold (with a
//        reason that stays out of the ledger). Every ruling is sealed with the reviewer's key. Below:
//        the policy the next question is held under, and the signing identity.
//

import AppKit
import Bless
import BlessPlaygroundKit
import SwiftUI

struct ReviewerPane: View {
    @Environment(Session.self) private var session
    @Environment(ReviewerFocus.self) private var focus
    @State private var selection: Petition.ID?
    @State private var text = ""
    @State private var reason = ""
    @State private var note = ""
    @State private var editing: Petition.ID?
    @State private var showsPolicy = false
    @State private var showsIdentity = false

    private var selected: Petition? { session.pending.first { $0.id == selection } }
    private var changed: Bool { selected.map { text != $0.message.content } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Reviewer", subtitle: session.identity.party.displayName, symbol: "stethoscope", tint: Palette.reviewer,
                       badge: session.pending.count)
            bar
            queue
            Divider()
            if let petition = selected {
                detail(petition)
            } else {
                ContentUnavailableView("No reply is waiting", systemImage: "tray",
                                       description: Text("Held replies appear here. Nothing reaches the patient until you rule."))
            }
        }
        .onChange(of: session.pending.map(\.id)) { _, ids in
            if selection == nil || !ids.contains(selection!) { selection = ids.first }
        }
        .onChange(of: selection) { _, id in load(id) }
        .onChange(of: focus.requested?.at) { _, _ in
            guard let action = focus.requested?.action else { return }
            switch action {
            case .bless: rule(.bless)
            case .amend: if changed { rule(.amend(content: text)) }
            case .withhold: if !reason.isEmpty { rule(.withhold(reason: reason)) }
            }
        }
    }

    private var bar: some View {
        @Bindable var session = session
        return HStack(spacing: 8) {
            Button { showsPolicy = true } label: { Label("Policy", systemImage: "slider.horizontal.3") }
                .popover(isPresented: $showsPolicy, arrowEdge: .bottom) {
                    PolicyEditor(policy: $session.policy).padding(14).frame(width: 380)
                }
            Button { showsIdentity = true } label: { Label("Signing identity", systemImage: "signature") }
                .popover(isPresented: $showsIdentity, arrowEdge: .bottom) { IdentityCard().padding(14).frame(width: 360) }
            Spacer()
            Text(policySummary(session.policy)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var queue: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(session.pending) { petition in
                    Button { selection = petition.id } label: { QueueCard(petition: petition, selected: petition.id == selection) }
                        .buttonStyle(.plain)
                }
                if session.pending.isEmpty {
                    Text("Nothing waiting").font(.caption).foregroundStyle(.secondary).padding(.vertical, 18)
                }
                if !session.decided.isEmpty {
                    Divider().frame(height: 40)
                    ForEach(session.decided.prefix(6)) { petition in
                        Label(Format.standing(petition), systemImage: Format.symbol(petition.standing))
                            .font(.caption)
                            .foregroundStyle(Format.tint(petition.standing))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private func detail(_ petition: Petition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Held \(Format.time(petition.submitted)) · \(petition.provenance.model)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let deadline = petition.deadline { Countdown(deadline: deadline, policy: petition.policy.onLapse).font(.caption) }
                }
                GroupBox("Conversation the policy lets you see") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if petition.context.isEmpty { Text("None").foregroundStyle(.secondary) }
                            ForEach(Array(petition.context.enumerated()), id: \.offset) { _, message in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(message.role == .user ? "Patient" : "Sent").font(.caption.weight(.semibold))
                                        .foregroundStyle(message.role == .user ? Palette.patient : .secondary)
                                        .frame(width: 52, alignment: .leading)
                                    Text(message.content).font(.callout).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 132)
                }
                GroupBox(petition.policy.allowsAmendment ? "The model's draft: edit it to amend" : "The model's draft") {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .disabled(!petition.policy.allowsAmendment)
                }
                TextField("Note for the record (optional, sealed with the verdict)", text: $note).textFieldStyle(.roundedBorder)
                HStack {
                    Button(changed ? "Amend and Release" : "Bless") { rule(changed ? .amend(content: text) : .bless) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.reviewer)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if changed { Button("Revert") { text = petition.message.content } }
                    Spacer()
                    TextField("Reason to withhold", text: $reason).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Button("Withhold", role: .destructive) { rule(.withhold(reason: reason)) }
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = session.reviewerError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.failed)
                }
                Text("Your ruling is signed with your key \(session.identity.fingerprint) over this text's SHA-256 \(petition.digest.prefix)…")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(14)
        }
    }

    private func policySummary(_ policy: Policy) -> String {
        let deadline = policy.deadline.map { "deadline " + Format.countdown(TimeInterval($0.components.seconds)) } ?? "no deadline"
        return "\(deadline), then \(Format.lapse(policy.onLapse)) · next question"
    }

    private func load(_ id: Petition.ID?) {
        guard let id, let petition = session.pending.first(where: { $0.id == id }) else { return }
        if editing != id {
            editing = id
            text = petition.message.content
            reason = ""
            note = ""
        }
        Task { await session.view(id) }
    }

    private func rule(_ ruling: Ruling) {
        guard let id = selection else { return }
        let note = self.note
        Task { await session.decide(ruling, on: id, note: note) }
    }
}

private struct QueueCard: View {
    let petition: Petition
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(petition.recipient.displayName).font(.caption.weight(.semibold))
            Text(petition.proposed.content).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if let deadline = petition.deadline { Countdown(deadline: deadline).font(.caption2) }
        }
        .frame(width: 170, alignment: .leading)
        .padding(8)
        .background(Palette.reviewer.opacity(selected ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.reviewer.opacity(selected ? 0.9 : 0.25), lineWidth: selected ? 1.5 : 1))
    }
}

private struct Countdown: View {
    let deadline: Date
    var policy: Policy.Lapse?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = deadline.timeIntervalSince(context.date)
            Label(left > 0 ? Format.countdown(left) + (policy.map { " · then \(Format.lapse($0))" } ?? "") : "deadline passed",
                  systemImage: "timer")
                .monospacedDigit()
                .foregroundStyle(left < 30 ? Palette.withheld : .secondary)
        }
    }
}

private struct PolicyEditor: View {
    @Binding var policy: Policy

    private var deadlineSeconds: Binding<Int> {
        Binding(get: { policy.deadline.map { Int($0.components.seconds) } ?? 0 },
                set: { policy.deadline = $0 > 0 ? .seconds($0) : nil })
    }

    private var lapse: Binding<String> {
        Binding(get: { policy.onLapse.name }, set: { name in
            switch name {
            case "withhold": policy.onLapse = .withhold
            case "releaseFallback": policy.onLapse = .releaseFallback(Session.fallbackText)
            default: policy.onLapse = .hold
            }
        })
    }

    private var window: Binding<Int> {
        Binding(get: { policy.contextWindow ?? 0 }, set: { policy.contextWindow = $0 > 0 ? $0 : nil })
    }

    var body: some View {
        Form {
            Stepper(value: deadlineSeconds, in: 0...3600, step: 15) {
                Text("Deadline: \(deadlineSeconds.wrappedValue == 0 ? "none" : Format.countdown(TimeInterval(deadlineSeconds.wrappedValue)))")
            }
            Picker("At the deadline", selection: lapse) {
                Text("Hold (keep waiting)").tag("hold")
                Text("Withhold (send nothing)").tag("withhold")
                Text("Send a holding message").tag("releaseFallback")
            }
            Stepper(value: window, in: 0...40) {
                Text("Reviewer sees: \(window.wrappedValue == 0 ? "the whole conversation" : "the last \(window.wrappedValue) messages")")
            }
            Toggle("Reviewers may amend", isOn: $policy.allowsAmendment)
            Toggle("Verdicts must be sealed", isOn: $policy.requiresSeal)
            LabeledContent("Quorum", value: "1 of 1")
            Text("Changes apply to the next question.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.columns)
        .padding(.top, 4)
    }
}

private struct IdentityCard: View {
    @Environment(Session.self) private var session
    @State private var name = ""
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Display name", text: $name).textFieldStyle(.roundedBorder)
                    .onSubmit { session.renameReviewer(name) }
                Button("Rename") { session.renameReviewer(name) }.disabled(name == session.identity.party.displayName)
            }
            LabeledContent("Fingerprint") { Text(session.identity.fingerprint).font(.caption.monospaced()).textSelection(.enabled) }
            HStack {
                Button("Copy Public Key") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.identity.verifyingKey.base64EncodedString(), forType: .string)
                }
                Button("Regenerate…") { confirming = true }
            }
            Text("An Ed25519 key kept in Application Support for this demo. A real reviewer's key stays on their own device.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
        .onAppear { name = session.identity.party.displayName }
        .confirmationDialog("Make a new signing key?", isPresented: $confirming) {
            Button("Regenerate", role: .destructive) { session.regenerateIdentity() }
        } message: {
            Text("Verdicts already in the ledger stay signed by the old key.")
        }
    }
}
