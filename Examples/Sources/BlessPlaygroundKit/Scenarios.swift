//
//  Scenarios.swift
//  BlessPlaygroundKit
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Three invented patient questions to start a demo with, the system prompt the model
//        drafts under, and the replies the offline fake model gives: each fake reply has one
//        confident sentence a clinician would change, so Amend has something to do.
//  PIN:  Invented people and questions. Never type real patient data into the playground with a
//        hosted model's key: that provider would need a business associate agreement (HIPAA.md).
//

import Foundation

public struct Scenario: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let question: String
    public let fakeReply: String
}

public enum Scenarios {
    public static let systemPrompt = """
    You draft replies to a patient's messages for their general practitioner, who reviews every \
    draft before anything is sent. The patient sees only what the clinician releases. Write as the \
    care team, in plain words, in three sentences or fewer. Put anything urgent first. Never state a \
    diagnosis as certain and never change a prescription; say when the patient should call or come in.
    """

    public static let all: [Scenario] = [
        Scenario(id: "medication", title: "Ibuprofen with lisinopril",
                 question: "Can I take ibuprofen with my lisinopril for a sore knee?",
                 fakeReply: "Yes, ibuprofen is fine with lisinopril for a few days. Take 400 mg up to three times a day with food, and rest the knee."),
        Scenario(id: "fever", title: "A child's fever",
                 question: "My 4-year-old has had a 39 °C fever since last night. Should I bring her in?",
                 fakeReply: "A fever of 39 °C is common in young children and nothing to worry about. Give children's paracetamol and keep her drinking; there is no need to come in."),
        Scenario(id: "missed-dose", title: "A missed dose",
                 question: "I forgot my sertraline yesterday. Should I take two today to catch up?",
                 fakeReply: "Yes, take two tablets today to catch up, then carry on as usual tomorrow."),
    ]

    public static func named(_ id: String) -> Scenario? { all.first { $0.id == id } }

    /// The fake model's reply to a question: its scenario's, or a general one.
    public static func fakeReply(to question: String) -> String {
        let lower = question.lowercased()
        if lower.contains("ibuprofen") || lower.contains("lisinopril") { return all[0].fakeReply }
        if lower.contains("fever") || lower.contains("temperature") { return all[1].fakeReply }
        if lower.contains("forgot") || lower.contains("missed") || lower.contains("sertraline") { return all[2].fakeReply }
        return "Thanks for your message. What you describe is almost certainly nothing serious, and it should settle on its own within a few days."
    }
}
