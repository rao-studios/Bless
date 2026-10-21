//
//  ModelPane.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The operator's view of the model: which provider and model draft the replies, where the
//        key came from (never the key), and the current draft as it is written, with its phase
//        (drafting, held, released, withheld) and provenance (model, latency, the SHA-256 the
//        reviewer's verdict will pin). The patient never sees this pane's draft.
//

import Bless
import BlessPlaygroundKit
import SwiftUI

struct ModelPane: View {
    @Environment(Session.self) private var session
    @State private var showsKeySheet = false
    @State private var showsPrompt = false

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            PaneHeader(title: "Model", subtitle: session.settings.choice.label, symbol: "cpu", tint: Palette.model)
            Form {
                Section {
                    Picker("Provider", selection: $session.settings.choice) {
                        ForEach(ProviderChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: session.settings.choice) { _, choice in
                        if !choice.models.contains(session.settings.model) { session.settings.model = choice.models[0] }
                    }
                    HStack {
                        TextField("Model", text: $session.settings.model)
                        Menu {
                            ForEach(session.settings.choice.models, id: \.self) { model in
                                Button(model) { session.settings.model = model }
                            }
                        } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    if session.settings.choice == .openAICompatible {
                        TextField("Base URL", text: $session.settings.baseURL)
                    }
                    if session.settings.choice != .fake {
                        LabeledContent("Key") {
                            HStack {
                                Text(session.keySource?.label ?? "none")
                                    .foregroundStyle(session.keySource == nil ? Palette.withheld : .secondary)
                                    .lineLimit(1)
                                Button("Key…") { showsKeySheet = true }
                                Button("Check") { Task { await session.checkKey() } }
                            }
                        }
                        keyCheck
                    } else {
                        Label("The offline fake answers: no key, no network. Each reply has one confident sentence a clinician would change.",
                              systemImage: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("System prompt", isExpanded: $showsPrompt) {
                        Text(Scenarios.systemPrompt).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 330)
            Divider()
            DraftView(draft: session.draft)
        }
        .sheet(isPresented: $showsKeySheet) { KeySheet() }
    }

    @ViewBuilder private var keyCheck: some View {
        switch session.keyCheck {
        case .unchecked: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .passed(let models): Label("The key works: \(models) models available.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Palette.patient)
        case .failed(let why): Label(why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.failed).lineLimit(3)
        }
    }
}

private struct DraftView: View {
    let draft: DraftState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Draft").font(.headline)
                Spacer()
                PhaseChip(phase: draft.phase)
            }
            ScrollView {
                Text(draft.text.isEmpty ? "The model's draft appears here as it is written. It waits at the Gate until the reviewer rules." : draft.text)
                    .foregroundStyle(draft.text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if case .failed(let why) = draft.phase {
                Label(why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.failed).lineLimit(4)
            }
            if !draft.model.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Model").foregroundStyle(.secondary); Text(draft.model) }
                    if let latency = draft.latency { GridRow { Text("Written in").foregroundStyle(.secondary); Text(Format.seconds(latency)) } }
                    if let digest = draft.digest {
                        GridRow { Text("SHA-256").foregroundStyle(.secondary); Text(digest.prefix + "…").font(.caption.monospaced()) }
                    }
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct PhaseChip: View {
    let phase: DraftState.Phase

    var body: some View {
        Text(phase.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch phase {
        case .idle: .secondary
        case .drafting: Palette.model
        case .held: Palette.reviewer
        case .released(.lapsed): Palette.withheld
        case .released: Palette.patient
        case .withheld, .lapsed, .withdrawn: Palette.withheld
        case .failed: Palette.failed
        }
    }
}
