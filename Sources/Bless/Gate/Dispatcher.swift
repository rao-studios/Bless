//
//  Dispatcher.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The host's delivery path to a recipient (a push, a message in the patient's app, an
//        SSE chunk). `Gate.dispatch(_:via:)` hands it only a verified Release and records in
//        the ledger whether delivery succeeded.
//

import Foundation

public protocol Dispatcher: Sendable {
    func dispatch(_ release: Release, to recipient: Party) async throws
}
