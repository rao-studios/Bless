//
//  ChatMessage.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: One turn of a conversation, in the shape every chat API shares: a role and its text.
//

import Foundation

public enum ChatRole: String, Codable, Sendable, CaseIterable {
    case system, user, assistant
}

public struct ChatMessage: Codable, Sendable, Equatable, Hashable {
    public var role: ChatRole
    public var content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage { ChatMessage(role: .system, content: content) }
    public static func user(_ content: String) -> ChatMessage { ChatMessage(role: .user, content: content) }
    public static func assistant(_ content: String) -> ChatMessage { ChatMessage(role: .assistant, content: content) }
}
