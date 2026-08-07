import Foundation

/// The deliberately small subset of a MiAuth response MissCat needs to create
/// an account. Unknown user fields are ignored so server-side model additions
/// cannot break authentication.
struct MissCatMiAuthCheckResponse: Decodable {
    struct User: Decodable, Equatable {
        let id: String
        let username: String
    }

    let ok: Bool
    let token: String?
    let user: User?
}

struct MissCatMiAuthHTTPResponse {
    let data: Data
    let statusCode: Int
}

protocol MissCatMiAuthTransport {
    func send(_ request: URLRequest) async throws -> MissCatMiAuthHTTPResponse
}

struct MissCatURLSessionMiAuthTransport: MissCatMiAuthTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> MissCatMiAuthHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MissCatMiAuthTransportError.missingHTTPResponse
        }
        return MissCatMiAuthHTTPResponse(data: data, statusCode: response.statusCode)
    }
}

enum MissCatMiAuthTransportError: Error {
    case missingHTTPResponse
}

struct MissCatInstance: Equatable {
    let origin: URL
    let identifier: String

    static func normalize(_ value: String) throws -> MissCatInstance {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              !host.hasSuffix("."),
              components.percentEncodedHost?.contains("%") != true,
              components.port.map({ (1 ... 65_535).contains($0) }) ?? true
        else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }

        components.scheme = "https"
        components.host = host
        components.path = ""
        if components.port == 443 {
            components.port = nil
        }

        guard let origin = components.url,
              origin.absoluteString.hasPrefix("https://")
        else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }

        let identifier = String(origin.absoluteString.dropFirst("https://".count))
        guard !identifier.isEmpty else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }
        return MissCatInstance(origin: origin, identifier: identifier)
    }
}

enum MissCatMiAuthRequestBuilder {
    static func authorizationURL(
        instance: MissCatInstance,
        sessionID: UUID,
        callbackURLString: String,
        permissions: [String]
    ) throws -> URL {
        guard let callbackURL = URL(string: callbackURLString),
              var components = URLComponents(url: instance.origin, resolvingAgainstBaseURL: false)
        else {
            throw MissCatAuthenticationService.AuthenticationError.invalidCallback
        }

        components.percentEncodedPath = "/miauth/\(sessionID.uuidString.lowercased())"
        components.queryItems = [
            URLQueryItem(name: "name", value: "MissCat"),
            URLQueryItem(name: "callback", value: callbackURL.absoluteString),
            URLQueryItem(name: "permission", value: permissions.joined(separator: ","))
        ]

        guard let url = components.url else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }
        return url
    }

    static func checkRequest(instance: MissCatInstance, sessionID: UUID) throws -> URLRequest {
        guard var components = URLComponents(url: instance.origin, resolvingAgainstBaseURL: false) else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }
        components.percentEncodedPath = "/api/miauth/\(sessionID.uuidString.lowercased())/check"
        guard let url = components.url else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return request
    }
}

/// Builds the authenticated identity request used to verify a credential after
/// it has crossed the persistence boundary. Keep the token out of the JSON
/// body so diagnostics can inspect the endpoint and payload shape without
/// serializing credential material.
enum MissCatAuthenticatedIdentityRequestBuilder {
    static func request(instance rawInstance: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else {
            throw MissCatAuthenticationService.AuthenticationError.missingAccessToken
        }

        let instance = try MissCatInstance.normalize(rawInstance)
        guard let url = URL(string: "/api/i", relativeTo: instance.origin)?.absoluteURL else {
            throw MissCatAuthenticationService.AuthenticationError.invalidInstance
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        return request
    }
}
