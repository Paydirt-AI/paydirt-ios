//
// PaydirtAPIClient.swift
// API client for Paydirt backend
//

import Foundation

actor PaydirtAPIClient {
    private let apiKey: String
    private let baseURL: String

    init(apiKey: String, baseURL: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    /// Fetch form details by ID or type
    /// Returns nil if form is not found or disabled (graceful handling for remote control)
    func getForm(formId: String? = nil, type: String? = nil) async throws -> PaydirtForm? {
        var urlComponents = URLComponents(string: "\(baseURL)/api/conversation/forms")!
        var queryItems: [URLQueryItem] = []

        if let formId = formId {
            queryItems.append(URLQueryItem(name: "form_id", value: formId))
        }
        if let type = type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaydirtError.apiError("Failed to fetch form")
        }

        // 404 means form not found or disabled - return nil for graceful handling
        if httpResponse.statusCode == 404 {
            PaydirtLogger.shared.info("API", "Form not found or disabled")
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw PaydirtError.apiError("Failed to fetch form")
        }

        let result = try JSONDecoder().decode(FormResponse.self, from: data)
        return result.form
    }

    /// Send a message and get follow-up question
    func sendMessage(
        formId: String,
        message: String,
        conversationHistory: [ConversationMessage]
    ) async throws -> FollowUpResponse {
        let url = URL(string: "\(baseURL)/api/conversation/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "form_id": formId,
            "message": message,
            "conversation_history": conversationHistory.map { ["role": $0.role, "content": $0.content] }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PaydirtError.apiError("Failed to send message")
        }

        return try JSONDecoder().decode(FollowUpResponse.self, from: data)
    }

    /// Submit completed conversation
    func submitResponse(
        formId: String,
        userId: String?,
        conversation: [ConversationMessage],
        metadata: [String: Any]?
    ) async throws {
        let url = URL(string: "\(baseURL)/api/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "form_id": formId,
            "conversation": conversation.map { ["role": $0.role, "content": $0.content] }
        ]

        if let userId = userId {
            body["user_id_external"] = userId
        }

        if let metadata = metadata {
            body["metadata"] = metadata
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw PaydirtError.apiError("Failed to submit response")
        }

        PaydirtLogger.shared.info("API", "Response submitted successfully")
    }

    /// Transcribe audio using Whisper via backend
    func transcribeAudio(audioData: Data) async throws -> String {
        let url = URL(string: "\(baseURL)/api/audio/transcribe")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 60  // Longer timeout for audio processing

        // Prepare multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Audio file parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PaydirtError.apiError("Failed to transcribe audio")
        }

        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
}

// MARK: - API Types

struct FormResponse: Codable {
    let form: PaydirtForm
}

struct PaydirtForm: Codable {
    let id: String
    let name: String
    let type: String
    let prompt: String
    let enabled: Bool?  // Optional for backwards compatibility
}

struct FollowUpResponse: Codable {
    let follow_up_question: String?
    let is_complete: Bool
}

struct ConversationMessage: Codable {
    let role: String
    let content: String
    let input_type: String?  // "text" or "audio", nil for assistant messages
}

struct TranscriptionResponse: Codable {
    let text: String
}

enum PaydirtError: Error, LocalizedError {
    case apiError(String)
    case notConfigured
    case formNotFound
    case formDisabled

    var errorDescription: String? {
        switch self {
        case .apiError(let message): return message
        case .notConfigured: return "Paydirt SDK not configured"
        case .formNotFound: return "Form not found or disabled"
        case .formDisabled: return "Form is currently disabled"
        }
    }
}
