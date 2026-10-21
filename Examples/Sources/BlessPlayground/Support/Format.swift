//
//  Format.swift
//  BlessPlayground
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The app's small shared pieces: the party colours (the README hero's: blue the model,
//        gold the reviewer and the seal, green the patient and a release, orange a withholding,
//        red a failure), the pane header, and the formats for times, waits and outcomes.
//

import Bless
import SwiftUI

enum Palette {
    static let model = Color(red: 0x5E / 255, green: 0x8F / 255, blue: 0xDA / 255)
    static let reviewer = Color(red: 0xC7 / 255, green: 0xA6 / 255, blue: 0x59 / 255)
    static let patient = Color(red: 0x28 / 255, green: 0xA8 / 255, blue: 0x83 / 255)
    static let withheld = Color(red: 0xD8 / 255, green: 0x77 / 255, blue: 0x3F / 255)
    static let failed = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
}

struct PaneHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            Text(title).font(.headline)
            Text(subtitle).foregroundStyle(.secondary)
            Spacer()
            if badge > 0 {
                Text("\(badge) waiting").font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(tint.opacity(0.2), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.06))
        .overlay(alignment: .bottom) { Rectangle().fill(tint.opacity(0.5)).frame(height: 2) }
    }
}

enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        countdown(max(0, now.timeIntervalSince(start)))
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f s", value)
    }

    static func basis(_ basis: Release.Basis, reviewer: String) -> String {
        switch basis {
        case .blessed: "Reviewed by \(reviewer)"
        case .amended: "Reviewed and edited by \(reviewer)"
        case .lapsed: "Holding message from your care team"
        }
    }

    static func lapse(_ lapse: Policy.Lapse) -> String {
        switch lapse {
        case .hold: "keep waiting"
        case .withhold: "send nothing"
        case .releaseFallback: "send a holding message"
        }
    }

    static func standing(_ petition: Petition) -> String {
        switch petition.standing {
        case .pending: "Waiting"
        case .blessed: petition.amended ? "Amended" : "Blessed"
        case .withheld: "Withheld"
        case .expired: petition.fallback == nil ? "Lapsed" : "Lapsed, holding message"
        case .withdrawn: "Withdrawn"
        }
    }

    static func symbol(_ standing: Petition.Standing) -> String {
        switch standing {
        case .pending: "hourglass"
        case .blessed: "checkmark.seal.fill"
        case .withheld: "hand.raised.fill"
        case .expired: "clock.badge.exclamationmark"
        case .withdrawn: "arrow.uturn.backward"
        }
    }

    static func tint(_ standing: Petition.Standing) -> Color {
        switch standing {
        case .pending: Palette.reviewer
        case .blessed: Palette.patient
        case .withheld, .expired, .withdrawn: Palette.withheld
        }
    }

    static func tint(_ kind: LedgerEvent.Kind) -> Color {
        switch kind {
        case .submitted, .viewed: Palette.model
        case .decided, .blessed: Palette.reviewer
        case .released, .dispatched: Palette.patient
        case .withheld, .expired, .withdrawn: Palette.withheld
        case .failed: Palette.failed
        }
    }
}
