//
//  KeySheet.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Where the operator gives the playground a Mistral key: a secure field that saves to this
//        app's Keychain item and is cleared at once, Forget (which removes only that item), and the
//        places the app looks, in order, with the one in use marked. The key is never shown.
//

import BlessPlaygroundKit
import SwiftUI

struct KeySheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mistral key").font(.title3.weight(.semibold))
            SecureField("Paste a key from console.mistral.ai", text: $entry)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
            VStack(alignment: .leading, spacing: 4) {
                Text("The playground looks, in order, in:").font(.caption).foregroundStyle(.secondary)
                source("1. this app's Keychain item", active: session.keySource == .keychain)
                source("2. MISTRAL_API_KEY in the environment", active: session.keySource == .environment)
                source("3. ~/.rao/keys/providers.json", active: { if case .raoKeys = session.keySource { true } else { false } }())
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.failed) }
            HStack {
                Button("Forget This App's Key", role: .destructive) { run { try await session.forgetKey() } }
                    .disabled(session.keySource != .keychain || working)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save to Keychain") {
                    let text = entry
                    entry = ""
                    run {
                        try await session.saveKey(text)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(20)
    }

    private func source(_ text: String, active: Bool) -> some View {
        Label(text, systemImage: active ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(active ? Palette.patient : .secondary)
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        working = true
        error = nil
        Task {
            do { try await action() } catch { self.error = String(describing: error) }
            working = false
        }
    }
}
