import Foundation

protocol DoNotMissBackendClient {
    func upsertUser(email: String, name: String?) async throws
    func fetchLatestMessage(
        email: String,
        appVersion: String,
        workflow: DoNotMissMessageWorkflow,
        language: DoNotMissBackendLanguage
    ) async throws -> DoNotMissLatestMessageResponseDTO
    func recordImpression(messageId: String, payload: DoNotMissImpressionRequestDTO) async throws -> DoNotMissImpressionResponseDTO
    func recordCTAClick(messageId: String, googleEmail: String) async throws
}

extension DoNotMissBackendClient {
    func fetchLatestMessage(email: String) async throws -> DoNotMissLatestMessageResponseDTO {
        try await fetchLatestMessage(
            email: email,
            appVersion: AppVersionProvider.resolved(),
            workflow: .startingApp,
            language: DoNotMissBackendLanguageResolver.resolveCurrentLanguage()
        )
    }
}

enum DoNotMissBackendError: LocalizedError {
    case invalidBaseURL(String)
    case invalidRequestPath(String)
    case invalidParameter(name: String)
    case invalidResponse
    case encodingFailed(String)
    case decodingFailed(String)
    case httpError(statusCode: Int, message: String?)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid backend base URL: \(value)"
        case .invalidRequestPath(let path):
            return "Invalid backend request path: \(path)"
        case .invalidParameter(let name):
            return "Invalid backend parameter: \(name)"
        case .invalidResponse:
            return "Invalid backend response"
        case .encodingFailed(let details):
            return "Failed to encode backend payload: \(details)"
        case .decodingFailed(let details):
            return "Failed to decode backend payload: \(details)"
        case .httpError(let statusCode, let message):
            if let message, message.isEmpty == false {
                return "Backend HTTP \(statusCode): \(message)"
            }
            return "Backend HTTP \(statusCode)"
        case .networkError(let details):
            return "Backend network error: \(details)"
        }
    }
}

final class DoNotMissBackendService: DoNotMissBackendClient {
    typealias DataTask = (URLRequest) async throws -> (Data, URLResponse)

    private struct EmptyResponse: Decodable {}

    private struct ServerMessageEnvelope: Decodable {
        let message: String?
        let error: ServerError?

        struct ServerError: Decodable {
            let message: String?
        }
    }

    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let performDataTask: DataTask

    init(
        baseURLString: String = DoNotMissBackendConfig.resolvedBaseURLString,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        performDataTask: DataTask? = nil
    ) throws {
        guard let baseURL = URL(string: baseURLString),
              let scheme = baseURL.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw DoNotMissBackendError.invalidBaseURL(baseURLString)
        }

        self.baseURL = baseURL
        self.decoder = decoder
        self.encoder = encoder
        self.performDataTask = performDataTask ?? { request in
            try await urlSession.data(for: request)
        }
    }

    func upsertUser(email: String, name: String?) async throws {
        let normalizedEmail = try validatedNormalizedEmail(email)
        let payload = DoNotMissUpsertUserRequestDTO(email: normalizedEmail, name: normalizedName(name))
        _ = try await request(
            method: "POST",
            path: "/api/client/users/upsert",
            queryItems: nil,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func fetchLatestMessage(
        email: String,
        appVersion: String,
        workflow: DoNotMissMessageWorkflow,
        language: DoNotMissBackendLanguage
    ) async throws -> DoNotMissLatestMessageResponseDTO {
        let normalizedEmail = try validatedNormalizedEmail(email)
        let appVersionValue = normalizedAppVersion(appVersion)
        return try await request(
            method: "GET",
            path: "/api/client/messages/latest",
            queryItems: [
                URLQueryItem(name: "email", value: normalizedEmail),
                URLQueryItem(name: "appVersion", value: appVersionValue),
                URLQueryItem(name: "workflow", value: workflow.rawValue),
                URLQueryItem(name: "language", value: language.rawValue)
            ],
            responseType: DoNotMissLatestMessageResponseDTO.self
        )
    }

    func recordImpression(
        messageId: String,
        payload: DoNotMissImpressionRequestDTO
    ) async throws -> DoNotMissImpressionResponseDTO {
        let messageID = try validatedMessageID(messageId)
        let normalizedPayload = DoNotMissImpressionRequestDTO(
            googleEmail: try validatedNormalizedEmail(payload.googleEmail),
            appVersion: normalizedAppVersion(payload.appVersion),
            contextEventId: normalizedOptionalField(payload.contextEventId),
            contextEventStartAt: normalizedOptionalField(payload.contextEventStartAt)
        )
        return try await request(
            method: "POST",
            path: "/api/client/messages/\(encodedPathComponent(messageID))/impression",
            queryItems: nil,
            body: normalizedPayload,
            responseType: DoNotMissImpressionResponseDTO.self
        )
    }

    func recordCTAClick(messageId: String, googleEmail: String) async throws {
        let messageID = try validatedMessageID(messageId)
        let payload = DoNotMissCTAClickRequestDTO(googleEmail: try validatedNormalizedEmail(googleEmail))
        _ = try await request(
            method: "POST",
            path: "/api/client/messages/\(encodedPathComponent(messageID))/cta-click",
            queryItems: nil,
            body: payload,
            responseType: EmptyResponse.self
        )
    }
}

private extension DoNotMissBackendService {
    func request<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        responseType: Response.Type
    ) async throws -> Response {
        let request = try makeRequest(method: method, path: path, queryItems: queryItems)
        return try await execute(request, method: method, path: path, responseType: responseType)
    }

    func request<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        body: Body?,
        responseType: Response.Type
    ) async throws -> Response {
        let request = try makeRequest(method: method, path: path, queryItems: queryItems, body: body)
        return try await execute(request, method: method, path: path, responseType: responseType)
    }

    func execute<Response: Decodable>(
        _ request: URLRequest,
        method: String,
        path: String,
        responseType: Response.Type
    ) async throws -> Response {
        debugLog("Request \(method) \(redactedURLString(for: request.url) ?? path)")
        do {
            let (data, response) = try await performDataTask(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DoNotMissBackendError.invalidResponse
            }

            debugLog("Response \(method) \(path) -> \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                let serverMessage = decodeServerMessage(from: data)
                throw DoNotMissBackendError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: serverMessage
                )
            }

            if Response.self == EmptyResponse.self || data.isEmpty {
                if let emptyResponse = EmptyResponse() as? Response {
                    return emptyResponse
                }
                throw DoNotMissBackendError.invalidResponse
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw DoNotMissBackendError.decodingFailed(error.localizedDescription)
            }
        } catch let error as DoNotMissBackendError {
            throw error
        } catch {
            throw DoNotMissBackendError.networkError(error.localizedDescription)
        }
    }

    func makeRequest<Body: Encodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        body: Body?
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DoNotMissBackendError.invalidRequestPath(path)
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let basePath = components.path == "/" ? "" : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedBasePath = basePath.isEmpty ? "" : "/\(basePath)"
        components.path = normalizedBasePath + normalizedPath
        components.queryItems = queryItems?.isEmpty == true ? nil : queryItems

        guard let url = components.url else {
            throw DoNotMissBackendError.invalidRequestPath(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw DoNotMissBackendError.encodingFailed(error.localizedDescription)
            }
        }

        return request
    }

    func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?
    ) throws -> URLRequest {
        try makeRequest(method: method, path: path, queryItems: queryItems, body: Optional<String>.none)
    }

    func decodeServerMessage(from data: Data) -> String? {
        guard data.isEmpty == false else {
            return nil
        }

        if let envelope = try? decoder.decode(ServerMessageEnvelope.self, from: data) {
            return envelope.message ?? envelope.error?.message
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func validatedNormalizedEmail(_ email: String) throws -> String {
        let normalized = normalizedEmail(email)
        guard normalized.isEmpty == false else {
            throw DoNotMissBackendError.invalidParameter(name: "email")
        }
        return normalized
    }

    func normalizedName(_ name: String?) -> String? {
        guard let name else {
            return nil
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedAppVersion(_ appVersion: String) -> String {
        let trimmed = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    func normalizedOptionalField(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func validatedMessageID(_ messageID: String) throws -> String {
        let trimmed = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw DoNotMissBackendError.invalidParameter(name: "messageId")
        }
        return trimmed
    }

    func encodedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func debugLog(_ message: String) {
        #if DEBUG
        print("[DoNotMissBackendService] \(message)")
        #endif
    }

    func redactedURLString(for url: URL?) -> String? {
        guard let url else {
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              items.isEmpty == false else {
            return url.absoluteString
        }

        components.queryItems = items.map { item in
            guard item.name == "email", let value = item.value else {
                return item
            }

            return URLQueryItem(name: item.name, value: maskedEmailForDebug(value))
        }

        return components.url?.absoluteString ?? url.absoluteString
    }

    func maskedEmailForDebug(_ email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = normalized.firstIndex(of: "@") else {
            return "***"
        }
        let localPart = String(normalized[..<atIndex])
        let domainPart = String(normalized[atIndex...])
        let visiblePrefix = localPart.prefix(2)
        return "\(visiblePrefix)***\(domainPart)"
    }
}
