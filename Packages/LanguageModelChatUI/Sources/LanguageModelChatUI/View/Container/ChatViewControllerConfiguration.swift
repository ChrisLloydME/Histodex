//
//  ChatViewControllerConfiguration.swift
//  LanguageModelChatUI
//

import MarkdownView
import UIKit

public extension ChatViewController {
    @MainActor
    struct Configuration {
        public var isReadOnly: Bool
        public var input: ChatInputConfiguration
        public var messageTheme: MarkdownTheme

        public init(
            isReadOnly: Bool = false,
            input: ChatInputConfiguration = .default,
            messageTheme: MarkdownTheme = .default
        ) {
            self.isReadOnly = isReadOnly
            self.input = input
            self.messageTheme = messageTheme
        }
    }
}
