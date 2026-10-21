//
//  BlessProviders.swift
//  BlessProviders
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: The module's front page. One InferenceProvider, OpenAICompatibleProvider, speaks the
//        chat-completions wire every mainstream layer shares (choices[], server-sent events), with
//        presets for OpenAI, Mistral and AII's Sewn. Wrap it in Bless's Blessed and nothing it says
//        reaches a user unread.
//  PIN:  Kept out of the core so Bless itself never touches the network.
//
