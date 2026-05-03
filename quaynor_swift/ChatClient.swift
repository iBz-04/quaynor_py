//
//  ChatClient.swift
//  quaynor_swift
//

import Foundation

enum ChatClientError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case decodingFailed
    case streamEndedUnexpectedly

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .badStatus(let code):
            return "Server returned status \(code)."
        case .decodingFailed:
            return "Could not read server response."
        case .streamEndedUnexpectedly:
            return "Stream ended before completion."
        }
    }
}

struct ChatPayload: Encodable {
    let message: String
}

private struct StreamChunk: Decodable {
    var t: String?
    var done: Bool?
}

/// POSTs user text to the Python Quaynor backend (streaming NDJSON from `/chat/stream`).
enum ChatClient {
    /// Simulator: `http://127.0.0.1:8765`. On a physical device, use your Mac's LAN IP (e.g. `http://192.168.1.10:8765`).
    static var baseURL: URL = URL(string: "http://127.0.0.1:8765")!

    /// Streams model tokens as they arrive (see server `/chat/stream`).
    static func streamReply(message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "/chat/stream", relativeTo: baseURL)?.absoluteURL else {
                        throw ChatClientError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(ChatPayload(message: message))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ChatClientError.badStatus(-1)
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw ChatClientError.badStatus(http.statusCode)
                    }

                    var buffer = Data()
                    var finished = false

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)

                        while let newlineIndex = buffer.firstIndex(of: 10) {
                            let lineData = buffer[..<newlineIndex]
                            buffer.removeSubrange(...newlineIndex)

                            let trimmed = lineData.drop(while: { $0 == 13 })
                            guard !trimmed.isEmpty else { continue }

                            let chunk = try JSONDecoder().decode(StreamChunk.self, from: Data(trimmed))
                            if chunk.done == true {
                                finished = true
                                continuation.finish()
                                return
                            }
                            if let token = chunk.t {
                                continuation.yield(token)
                            }
                        }
                    }

                    if !finished {
                        continuation.finish(throwing: ChatClientError.streamEndedUnexpectedly)
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    static func resetConversation() async throws {
        guard let url = URL(string: "/reset", relativeTo: baseURL)?.absoluteURL else {
            throw ChatClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ChatClientError.badStatus(-1)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw ChatClientError.badStatus(http.statusCode)
        }
    }
}
