import Foundation

/// Supplies and refreshes the session token. Kept as a protocol so the 401 path is testable
/// without a Supabase project (T-12).
public protocol SessionProviding: Sendable {
    func accessToken() async throws -> String
    /// Returns the new token, or throws if the session is genuinely over.
    func refresh() async throws -> String
    func signOut() async
}

/// The one place the device talks to the gateway.
///
/// It carries a session token and nothing else. No provider credential, no service-role key,
/// and no signing key passes through this type — that asymmetry is the product (§1 rule 1).
public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let sessionProvider: any SessionProviding
    private let clientVersion: String

    /// Exposed for tests: how many requests actually went out (T-10).
    public private(set) var requestCount = 0
    /// Exposed for tests: how many refreshes were attempted (T-12).
    public private(set) var refreshCount = 0

    public init(
        baseURL: URL,
        sessionProvider: any SessionProviding,
        clientVersion: String = "0.1.0",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.sessionProvider = sessionProvider
        self.clientVersion = clientVersion
        self.session = session
    }

    // MARK: - Requests

    public func send(_ endpoint: Endpoint) async throws -> Data {
        let token = try await tokenOrThrow()
        do {
            return try await perform(endpoint, token: token)
        } catch WarrantError.unauthorized {
            // Exactly one refresh, exactly one retry, then a clean sign out. Looping here
            // would hammer the gateway with a dead session.
            refreshCount += 1
            guard let refreshed = try? await sessionProvider.refresh() else {
                await sessionProvider.signOut()
                throw WarrantError.unauthorized
            }
            do {
                return try await perform(endpoint, token: refreshed)
            } catch WarrantError.unauthorized {
                await sessionProvider.signOut()
                throw WarrantError.unauthorized
            }
        }
    }

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await send(endpoint)
        do {
            return try WarrantJSON.decoder.decode(T.self, from: data)
        } catch {
            throw WarrantError.decoding
        }
    }

    private func tokenOrThrow() async throws -> String {
        do {
            return try await sessionProvider.accessToken()
        } catch {
            throw WarrantError.unauthorized
        }
    }

    private func perform(_ endpoint: Endpoint, token: String) async throws -> Data {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw WarrantError.notConfigured
        }
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw WarrantError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("ios/\(clientVersion)", forHTTPHeaderField: "X-Warrant-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = endpoint.idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        request.timeoutInterval = 15

        requestCount += 1

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WarrantError.network
        }

        guard let http = response as? HTTPURLResponse else { throw WarrantError.server }
        guard (200..<300).contains(http.statusCode) else {
            // A reason code in the body is more specific than the status, so it wins.
            if let code = Self.reasonCode(in: data) {
                throw WarrantError.from(reasonCode: code)
            }
            throw WarrantError.from(statusCode: http.statusCode)
        }
        return data
    }

    private static func reasonCode(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["code"] as? String
            ?? object["reason"] as? String
            ?? (object["error"] as? [String: Any])?["code"] as? String
    }
}
