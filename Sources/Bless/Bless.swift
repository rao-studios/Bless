//
//  Bless.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/13/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The module's front page. Bless holds a language model's reply until a person blesses it:
//        the reply becomes a Petition at a Gate, a reviewer rules on it (bless, amend or withhold),
//        and only a Release reaches the recipient. The pattern, for any InferenceProvider:
//
//            let gate = Gate()
//            let blessed = Blessed(upstream: model, gate: gate) { request in
//                Routing(conversationID: "visit-42", recipient: patient,
//                        reviewers: [doctor.party], policy: Policy(deadline: .seconds(4 * 3600)))
//            }
//            let reply = try await blessed.complete(request)   // returns only once it is blessed
//
//        and, on the reviewer's side, `try await gate.decide(id, .bless, as: doctor)`.
//  PIN:  No type is named Bless (the module's name); the version lives on BlessVersion.
//

/// The library's version, as the README and the site name it.
public enum BlessVersion {
    public static let string = "0.1.0"
}
