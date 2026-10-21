// swift-tools-version: 6.4
// Created by Ritesh Pakala on 10/13/26.
// Copyright © 2026 Rao Studios LLC.
//
// Bless — human-in-the-loop approval for a language model's replies. A reply the model drafts
// becomes a Petition; a trusted reviewer (a patient's GP, say) blesses, amends or withholds it;
// only a Release reaches the person who asked. Every ruling is sealed with the reviewer's key and
// every event is chained into a ledger, so what was sent, and who allowed it, can be proved later.
// Built with HIPAA's safeguards in mind: the ledger holds ids, digests and codes, never content;
// stores are private files, optionally AES-GCM sealed; reviewers see only the context the policy
// allows. Docs/site tells the design chapter by chapter; Docs/INTEGRATION.md is the guide to adopting it.
//
// Two products, two targets, in layers:
//   Bless           the core, Foundation + CryptoKit + Synchronization only, Swift 6 strict:
//                   Support/ (the SHA-256 value, canonical bytes, JSON coding, errors), Chat/ (the
//                   provider-facing shapes and InferenceProvider), Parties/ (Party, the reviewer's
//                   identity), Petition/ (Draft, Policy, Ruling, Verdict, Petition and its rules,
//                   Release), Seal/ (sign and verify), Ledger/ (the hash-chained audit log and its
//                   stores), Store/ (petition stores, private files, the cipher), Gate/ (the actor
//                   and the Dispatcher), Pattern/ (Blessed, the one way an inference layer adopts it)
//   BlessProviders  an OpenAI-compatible chat client over URLSession: presets (OpenAI, Mistral,
//                   AII's Sewn), the choices[] wire, server-sent events     (Foundation + Bless)
//
// Invariants PackageLayeringTests holds: exactly these two library products and no executable;
// Bless depends on nothing, BlessProviders on Bless alone; Bless imports Foundation, CryptoKit and
// Synchronization only, and CryptoKit in four named files; nothing under Sources/ imports SwiftUI,
// AppKit, UIKit, os, Combine or Logging, or calls print; Ledger/ never reads message content; no
// type is named like a module; every Swift file opens with its WHAT: header; platforms are
// macOS 15 and iOS 18 (AII's floor, and the patient's phone).
//
// No upcoming-feature flags: the module compiles in the same Swift 6 mode its consumers (AII,
// tools 6.2) do, so InferenceProvider's isolation means the same thing on both sides. The macOS
// playground that demonstrates the pattern against Mistral is a package of its own, Examples/.

import PackageDescription

let package = Package(
    name: "Bless",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Bless", targets: ["Bless"]),
        .library(name: "BlessProviders", targets: ["BlessProviders"]),
    ],
    targets: [
        .target(name: "Bless"),
        .target(name: "BlessProviders", dependencies: ["Bless"]),
        .testTarget(name: "BlessTests", dependencies: ["Bless"], exclude: ["Fixtures"]),
        .testTarget(name: "BlessProvidersTests", dependencies: ["BlessProviders", "Bless"]),
    ]
)
