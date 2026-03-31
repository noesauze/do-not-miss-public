import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

enum AuthServiceError: LocalizedError {
    case missingOAuthConfiguration
    case invalidAuthorizationURL
    case sessionFailedToStart
    case canceled
    case invalidCallbackURL
    case stateMismatch
    case authorizationCodeMissing
    case noStoredSession
    case accessTokenExpiredWithoutRefreshToken
    case invalidServerResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingOAuthConfiguration:
            return L10n.tr("auth.error.missing_oauth_configuration")
        case .invalidAuthorizationURL:
            return L10n.tr("auth.error.invalid_authorization_url")
        case .sessionFailedToStart:
            return L10n.tr("auth.error.session_failed_to_start")
        case .canceled:
            return L10n.tr("auth.error.canceled")
        case .invalidCallbackURL:
            return L10n.tr("auth.error.invalid_callback_url")
        case .stateMismatch:
            return L10n.tr("auth.error.state_mismatch")
        case .authorizationCodeMissing:
            return L10n.tr("auth.error.authorization_code_missing")
        case .noStoredSession:
            return L10n.tr("auth.error.no_stored_session")
        case .accessTokenExpiredWithoutRefreshToken:
            return L10n.tr("auth.error.access_token_expired_without_refresh_token")
        case .invalidServerResponse:
            return L10n.tr("auth.error.invalid_server_response")
        case .networkError(let details):
            return L10n.tr("error.network_with_details", details)
        }
    }
}

struct OAuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scope: String?
    let expiresAt: Date
    let idToken: String?
    let accountEmail: String?

    var isAccessTokenExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

@MainActor
final class AuthService: NSObject {
    private let keychainHelper: KeychainHelper
    private let urlSession: URLSession

    private var webAuthSession: ASWebAuthenticationSession?
    private(set) var currentSession: OAuthSession?

    var isSignedIn: Bool {
        currentSession != nil
    }

    var connectedAccountDescription: String {
        guard let currentSession else {
            return L10n.tr("auth.disconnected")
        }

        return currentSession.accountEmail ?? L10n.tr("auth.google_account")
    }

    init(
        keychainHelper: KeychainHelper = KeychainHelper(),
        urlSession: URLSession = .shared
    ) {
        self.keychainHelper = keychainHelper
        self.urlSession = urlSession
        self.currentSession = try? keychainHelper.loadCodable(
            service: GoogleOAuthConfig.keychainService,
            account: GoogleOAuthConfig.keychainAccount,
            as: OAuthSession.self
        )
        super.init()
    }

    func signIn() async throws {
        guard GoogleOAuthConfig.isConfigured else {
            throw AuthServiceError.missingOAuthConfiguration
        }

        let state = Self.randomURLSafeString(length: 32)
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(from: verifier)

        guard let authorizationURL = makeAuthorizationURL(state: state, codeChallenge: challenge) else {
            throw AuthServiceError.invalidAuthorizationURL
        }

        let callbackURL = try await authenticateInBrowser(startURL: authorizationURL)
        let authorizationCode = try Self.extractAuthorizationCode(from: callbackURL, expectedState: state)

        let tokenResponse = try await exchangeAuthorizationCodeForTokens(
            code: authorizationCode,
            codeVerifier: verifier
        )

        let session = OAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType,
            scope: tokenResponse.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            idToken: tokenResponse.idToken,
            accountEmail: Self.extractEmailFromIDToken(tokenResponse.idToken)
        )

        try persistSession(session)
        currentSession = session
    }

    func signOut() {
        do {
            try keychainHelper.delete(
                service: GoogleOAuthConfig.keychainService,
                account: GoogleOAuthConfig.keychainAccount
            )
        } catch {
            print("[AuthService] Keychain cleanup failed: \(error.localizedDescription)")
        }

        currentSession = nil
    }

    func restoreSessionFromKeychain() {
        currentSession = try? keychainHelper.loadCodable(
            service: GoogleOAuthConfig.keychainService,
            account: GoogleOAuthConfig.keychainAccount,
            as: OAuthSession.self
        )
    }

    func getValidAccessToken() async throws -> String {
        guard var session = currentSession else {
            throw AuthServiceError.noStoredSession
        }

        if !session.isAccessTokenExpired {
            return session.accessToken
        }

        guard let refreshToken = session.refreshToken else {
            throw AuthServiceError.accessTokenExpiredWithoutRefreshToken
        }

        let refreshResponse = try await refreshAccessToken(refreshToken: refreshToken)

        // Google may omit refresh_token on refresh responses, so we keep the previous one.
        session = OAuthSession(
            accessToken: refreshResponse.accessToken,
            refreshToken: refreshResponse.refreshToken ?? session.refreshToken,
            tokenType: refreshResponse.tokenType,
            scope: refreshResponse.scope ?? session.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(refreshResponse.expiresIn)),
            idToken: refreshResponse.idToken ?? session.idToken,
            accountEmail: Self.extractEmailFromIDToken(refreshResponse.idToken) ?? session.accountEmail
        )

        try persistSession(session)
        currentSession = session

        return session.accessToken
    }
}

private extension AuthService {
    struct GoogleTokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
        let scope: String?
        let tokenType: String
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
            case tokenType = "token_type"
            case idToken = "id_token"
        }
    }

    struct GoogleErrorResponse: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    func persistSession(_ session: OAuthSession) throws {
        try keychainHelper.saveCodable(
            session,
            service: GoogleOAuthConfig.keychainService,
            account: GoogleOAuthConfig.keychainAccount
        )
    }

    func makeAuthorizationURL(state: String, codeChallenge: String) -> URL? {
        var components = URLComponents(url: GoogleOAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.calendarEventsScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        return components?.url
    }

    func authenticateInBrowser(startURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: GoogleOAuthConfig.callbackURLScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil

                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: AuthServiceError.canceled)
                        return
                    }

                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AuthServiceError.invalidCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session

            if session.start() == false {
                self.webAuthSession = nil
                continuation.resume(throwing: AuthServiceError.sessionFailedToStart)
            }
        }
    }

    func exchangeAuthorizationCodeForTokens(code: String, codeVerifier: String) async throws -> GoogleTokenResponse {
        let parameters = [
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": GoogleOAuthConfig.redirectURI,
            "grant_type": "authorization_code"
        ]

        return try await requestToken(parameters: parameters)
    }

    func refreshAccessToken(refreshToken: String) async throws -> GoogleTokenResponse {
        let parameters = [
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        return try await requestToken(parameters: parameters)
    }

    func requestToken(parameters: [String: String]) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedData(from: parameters)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthServiceError.invalidServerResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                guard let tokenResponse = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data) else {
                    throw AuthServiceError.invalidServerResponse
                }

                return tokenResponse
            }

            if let serverError = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data) {
                throw AuthServiceError.networkError(serverError.errorDescription ?? serverError.error)
            }

            throw AuthServiceError.networkError("HTTP \(httpResponse.statusCode)")
        } catch {
            if error is AuthServiceError {
                throw error
            }

            throw AuthServiceError.networkError(error.localizedDescription)
        }
    }

    static func extractAuthorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthServiceError.invalidCallbackURL
        }

        let queryItems = components.queryItems ?? []

        if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
            throw AuthServiceError.networkError(oauthError)
        }

        let callbackState = queryItems.first(where: { $0.name == "state" })?.value
        guard callbackState == expectedState else {
            throw AuthServiceError.stateMismatch
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              code.isEmpty == false else {
            throw AuthServiceError.authorizationCodeMissing
        }

        return code
    }

    static func extractEmailFromIDToken(_ idToken: String?) -> String? {
        guard let idToken else {
            return nil
        }

        let segments = idToken.split(separator: ".")
        guard segments.count == 3 else {
            return nil
        }

        let payloadSegment = String(segments[1])
        guard let payloadData = base64URLDecode(payloadSegment),
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        return object["email"] as? String
    }

    static func randomURLSafeString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    static func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func formURLEncodedData(from parameters: [String: String]) -> Data {
        let body = parameters
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }

    static func urlEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
