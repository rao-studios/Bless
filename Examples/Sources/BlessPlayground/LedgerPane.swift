//
//  LedgerPane.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The Gate's audit log as a table: each event's seq, time, kind, actor, code and digest,
//        and whether the chain still verifies. It holds no message text, only digests: compare the
//        digest here with the one under the Model pane's draft. Export writes the JSON lines that the
//        integration guide's Python check reads.
//

import Bless
import BlessPlaygroundKit
import SwiftUI
import UniformTypeIdentifiers

struct LedgerPane: View {
    @Environment(Session.self) private var session
    @State private var exporting = false

    private struct Row: Identifiable {
        let event: LedgerEvent
        var id: Int { event.seq }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Ledger", systemImage: "link").font(.headline)
                Text("\(session.events.count) events, chained by SHA-256; no message text").font(.caption).foregroundStyle(.secondary)
                Spacer()
                chainStatus
                Button("Verify Chain") { session.verifyLedger() }
                Button("Export JSONL…") { exporting = true }.disabled(session.events.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Table(session.events.reversed().map(Row.init)) {
                TableColumn("#") { Text("\($0.event.seq)").monospacedDigit() }.width(36)
                TableColumn("Time") { Text(Format.time($0.event.at)).monospacedDigit() }.width(96)
                TableColumn("Kind") { row in
                    Text(row.event.kind.rawValue).foregroundStyle(Format.tint(row.event.kind))
                }.width(80)
                TableColumn("Petition") { Text($0.event.petitionID.rawValue.prefix(8)).font(.caption.monospaced()) }.width(80)
                TableColumn("Actor") { Text($0.event.actor?.rawValue ?? "") }.width(min: 70, ideal: 90)
                TableColumn("Code") { Text($0.event.code ?? "") }.width(min: 60, ideal: 80)
                TableColumn("Digest") { Text($0.event.digest.map { $0.prefix + "…" } ?? "").font(.caption.monospaced()) }.width(min: 100, ideal: 120)
                TableColumn("Hash") { Text($0.event.hash.prefix + "…").font(.caption.monospaced()).foregroundStyle(.secondary) }.width(min: 100, ideal: 120)
            }
        }
        .fileExporter(isPresented: $exporting, document: LedgerDocument(data: session.exportLedger()),
                      contentType: .ledgerLines, defaultFilename: "bless-ledger.jsonl") { _ in }
    }

    @ViewBuilder private var chainStatus: some View {
        switch session.chain {
        case .unchecked: EmptyView()
        case .intact(let count): Label("\(count) verified", systemImage: "checkmark.seal").foregroundStyle(Palette.patient).font(.caption)
        case .broken(let seq): Label("breaks at \(seq)", systemImage: "xmark.seal").foregroundStyle(Palette.failed).font(.caption)
        }
    }
}

struct LedgerDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.ledgerLines]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let ledgerLines = UTType(filenameExtension: "jsonl", conformingTo: .json) ?? .json
}
