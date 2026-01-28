//
// PaydirtAPIClient.swift
// API client for Paydirt backend
//

import Foundation

/// Error type to wrap HTTP status codes for retry logic
struct HTTPStatusError: Error {
    let statusCode: Int
    let message: String
}

actor PaydirtAPIClient {
    private let apiKey: String
    private let baseURL: String

    init(apiKey: String, baseURL: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: - Retry Logic

    /// Retry helper with exponential backoff for transient network failures
    /// Retries on: timeout, network loss, HTTP 503, HTTP 429
    /// Does NOT retry on: 400, 401, 403, 404 (client errors)
    private func withRetry<T>(
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 0.5,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if this is a retryable error
                guard attempt < maxRetries && isRetryableError(error) else {
                    throw error
                }

                // Calculate delay with exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt))
                PaydirtLogger.shared.info("API", "Request failed, retrying in \(delay)s (attempt \(attempt + 1)/\(maxRetries))")

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // Should not reach here, but throw last error just in case
        throw lastError ?? PaydirtError.apiError("Unknown error during retry")
    }

    /// Determine if an error is retryable (transient network issues)
    private func isRetryableError(_ error: Error) -> Bool {
        // Check for URLError network issues
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .notConnectedToInternet, .networkConnectionLost:
                return true
            default:
                return false
            }
        }

        // Check for HTTP status code errors (503, 429 are retryable)
        if let httpError = error as? HTTPStatusError {
            return httpError.statusCode == 503 || httpError.statusCode == 429
        }

        return false
    }

    /// Fetch form details by ID or type
    /// Returns nil if form is not found or disabled (graceful handling for remote control)
    func getForm(formId: String? = nil, type: String? = nil) async throws -> PaydirtForm? {
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/conversation/forms") else {
            throw PaydirtError.invalidURL
        }
        var queryItems: [URLQueryItem] = []

        if let formId = formId {
            queryItems.append(URLQueryItem(name: "form_id", value: formId))
        }
        if let type = type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw PaydirtError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30

        let (data, httpResponse) = try await withRetry {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PaydirtError.apiError("Failed to fetch form")
            }
            // Throw retryable status codes so withRetry can handle them
            if httpResponse.statusCode == 503 || httpResponse.statusCode == 429 {
                throw HTTPStatusError(statusCode: httpResponse.statusCode, message: "Server temporarily unavailable")
            }
            return (data, httpResponse)
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
        conversationHistory: [ConversationMessage],
        appContext: String? = nil
    ) async throws -> FollowUpResponse {
        guard let url = URL(string: "\(baseURL)/api/conversation/message") else {
            throw PaydirtError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "form_id": formId,
            "message": message,
            "conversation_history": conversationHistory.map { msg -> [String: Any] in
                var d: [String: Any] = ["role": msg.role, "content": msg.content]
                if let inputType = msg.input_type {
                    d["input_type"] = inputType
                }
                return d
            }
        ]

        if let appContext = appContext, !appContext.isEmpty {
            body["app_context"] = appContext
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await withRetry {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PaydirtError.apiError("Failed to send message")
            }
            // Throw retryable status codes so withRetry can handle them
            if httpResponse.statusCode == 503 || httpResponse.statusCode == 429 {
                throw HTTPStatusError(statusCode: httpResponse.statusCode, message: "Server temporarily unavailable")
            }
            guard httpResponse.statusCode == 200 else {
                throw PaydirtError.apiError("Failed to send message")
            }
            return data
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
        guard let url = URL(string: "\(baseURL)/api/responses") else {
            throw PaydirtError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "form_id": formId,
            "conversation": conversation.map { msg -> [String: Any] in
                var d: [String: Any] = ["role": msg.role, "content": msg.content]
                if let inputType = msg.input_type {
                    d["input_type"] = inputType
                }
                return d
            }
        ]

        if let userId = userId {
            body["user_id_external"] = userId
        }

        if let metadata = metadata {
            body["metadata"] = metadata
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        try await withRetry {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PaydirtError.apiError("Failed to submit response")
            }
            // Throw retryable status codes so withRetry can handle them
            if httpResponse.statusCode == 503 || httpResponse.statusCode == 429 {
                throw HTTPStatusError(statusCode: httpResponse.statusCode, message: "Server temporarily unavailable")
            }
            guard httpResponse.statusCode == 201 else {
                throw PaydirtError.apiError("Failed to submit response")
            }
        }

        PaydirtLogger.shared.info("API", "Response submitted successfully")
    }

    /// Transcribe audio using Whisper via backend
    func transcribeAudio(audioData: Data) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/audio/transcribe") else {
            throw PaydirtError.invalidURL
        }
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

        let data = try await withRetry {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PaydirtError.apiError("Failed to transcribe audio")
            }
            // Throw retryable status codes so withRetry can handle them
            if httpResponse.statusCode == 503 || httpResponse.statusCode == 429 {
                throw HTTPStatusError(statusCode: httpResponse.statusCode, message: "Server temporarily unavailable")
            }
            guard httpResponse.statusCode == 200 else {
                throw PaydirtError.apiError("Failed to transcribe audio")
            }
            return data
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
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .apiError(let message): return message
        case .notConfigured: return "Paydirt SDK not configured"
        case .formNotFound: return "Form not found or disabled"
        case .formDisabled: return "Form is currently disabled"
        case .invalidURL: return "Invalid API URL configuration"
        }
    }
}
