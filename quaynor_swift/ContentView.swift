//
//  ContentView.swift
//  quaynor_swift
//

import SwiftUI
import Foundation

/// Compact presence dot above the transcript (solid green).
private let chatPartnerGreen = Color(red: 0.29, green: 0.72, blue: 0.38)

/// Outgoing bubble color aligned with Messages (~ #007AFF).
private let userBubbleBlue = Color(red: 0.0, green: 0.478431, blue: 1.0)


/// Rounded “cap” corners (Messages-like).
private let bubbleCornerLarge: CGFloat = 20
/// Tighter radius on the bottom corner toward the transcript center (tail side).
private let bubbleCornerTail: CGFloat = 6

/// Asymmetric bubble matching Messages: generous continuous rounding, slightly sharper tail corner.
private func messageBubbleShape(isFromUser: Bool) -> UnevenRoundedRectangle {
    if isFromUser {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: bubbleCornerLarge,
                bottomLeading: bubbleCornerLarge,
                bottomTrailing: bubbleCornerTail,
                topTrailing: bubbleCornerLarge
            ),
            style: .continuous
        )
    } else {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: bubbleCornerLarge,
                bottomLeading: bubbleCornerTail,
                bottomTrailing: bubbleCornerLarge,
                topTrailing: bubbleCornerLarge
            ),
            style: .continuous
        )
    }
}

private struct ChatBubble: Identifiable {
    let id: UUID
    let role: Role
    var text: String

    enum Role {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Collapses runaway blank lines and replaces Unicode dash glyphs so text matches the assistant style we ask for.
private func displayNormalizedMarkdown(_ raw: String) -> String {
    var s = raw
    s = s.replacingOccurrences(of: "\u{2014}", with: ", ")
    s = s.replacingOccurrences(of: "\u{2013}", with: "-")
    while s.contains("\n\n\n") {
        s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    return s
}

/// Renders model Markdown with readable spacing; normalizes dashes for display.
private struct AssistantMarkdownText: View {
    var markdown: String

    private var normalized: String { displayNormalizedMarkdown(markdown) }

    var body: some View {
        Group {
            if markdown.isEmpty {
                Text(" ")
                    .font(.body)
                    .foregroundStyle(.clear)
            } else if let parsed = try? AttributedString(
                markdown: normalized,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                Text(parsed)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .textSelection(.enabled)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            } else {
                Text(normalized)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentView: View {
    @State private var messages: [ChatBubble] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorText: String?

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if messages.isEmpty {
                            Text("Ask anything")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        }

                        ForEach(messages) { bubble in
                            bubbleRow(bubble)
                                .id(bubble.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: messages.last?.text) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let errorText {
                        Text(errorText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                    }

                    composer
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1)
                        }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Circle()
                        .fill(chatPartnerGreen)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Online")
                }
                ToolbarItem(placement: .principal) {
                    Text("Chat")
                        .font(.headline.weight(.semibold))
                        .tracking(0.3)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await clearServerAndLocal() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isSending)
                    .accessibilityLabel("Clear conversation")
                }
            }
        }
        .tint(.primary)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $draft, prompt: Text("Message").foregroundStyle(.tertiary), axis: .vertical)
                .lineLimit(1 ... 6)
                .font(.body)
                .textFieldStyle(.plain)

            Button {
                Task { await send() }
            } label: {
                Group {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(canSend ? Color(.systemBackground) : Color.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(canSend && !isSending ? Color.primary : Color.secondary.opacity(0.15))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSending || !canSend)
            .animation(.easeOut(duration: 0.15), value: canSend)
            .animation(.easeOut(duration: 0.15), value: isSending)
        }
    }

    private func bubbleRow(_ bubble: ChatBubble) -> some View {
        let isFromUser = bubble.role == .user
        let shape = messageBubbleShape(isFromUser: isFromUser)

        return HStack(alignment: .bottom, spacing: 0) {
            if isFromUser {
                Spacer(minLength: 48)
            }

            Group {
                if isFromUser {
                    Text(bubble.text)
                        .foregroundStyle(Color.white)
                } else {
                    AssistantMarkdownText(markdown: bubble.text)
                }
            }
            .font(.body)
            .multilineTextAlignment(isFromUser ? .trailing : .leading)
                .padding(.horizontal, isFromUser ? 14 : 16)
                .padding(.vertical, isFromUser ? 10 : 13)
                .background {
                    shape
                        .fill(isFromUser ? userBubbleBlue : Color(.secondarySystemBackground))
                }
                .clipShape(shape)
                .overlay {
                    if !isFromUser {
                        shape
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                }

            if !isFromUser {
                Spacer(minLength: 48)
            }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        errorText = nil
        draft = ""
        messages.append(ChatBubble(role: .user, text: text))
        isSending = true
        defer { isSending = false }

        let assistantId = UUID()
        messages.append(ChatBubble(id: assistantId, role: .assistant, text: ""))

        do {
            guard let assistantIndex = messages.firstIndex(where: { $0.id == assistantId }) else { return }

            for try await token in ChatClient.streamReply(message: text) {
                var bubble = messages[assistantIndex]
                bubble.text += token
                messages[assistantIndex] = bubble
            }

            if messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
                errorText = "No reply from model."
            }
        } catch is CancellationError {
            if let assistantIndex = messages.firstIndex(where: { $0.id == assistantId }),
               messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
        } catch {
            if let assistantIndex = messages.firstIndex(where: { $0.id == assistantId }),
               messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
            errorText = error.localizedDescription
        }
    }

    private func clearServerAndLocal() async {
        errorText = nil
        messages.removeAll()
        do {
            try await ChatClient.resetConversation()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
