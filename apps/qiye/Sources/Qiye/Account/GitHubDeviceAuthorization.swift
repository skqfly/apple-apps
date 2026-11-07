import Foundation

struct GitHubDeviceCode: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code"
        case verificationURI = "verification_uri", expiresIn = "expires_in", interval
    }
}

actor GitHubDeviceAuthorization {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    func start(clientID: String) async throws -> GitHubDeviceCode {
        let data = try await post("https://github.com/login/device/code", values: [
            "client_id": clientID, "scope": "public_repo read:user"
        ])
        guard let code = try? JSONDecoder().decode(GitHubDeviceCode.self, from: data),
              code.verificationURI.scheme == "https", code.verificationURI.host == "github.com",
              code.expiresIn > 0, code.interval > 0 else {
            throw AuthorizationFailure.notConfigured
        }
        return code
    }

    func waitForToken(clientID: String, code: GitHubDeviceCode) async throws -> GitHubCredential {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = max(code.interval, 5)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            try Task.checkCancellation()
            let data = try await post("https://github.com/login/oauth/access_token", values: [
                "client_id": clientID, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            let reply = try JSONDecoder().decode(TokenReply.self, from: data)
            if let token = reply.accessToken, !token.isEmpty {
                let scopes = Set((reply.scope ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                guard scopes.contains("public_repo") || scopes.contains("repo") else {
                    throw AuthorizationFailure.permissionMissing
                }
                return GitHubCredential(accessToken: token, refreshToken: reply.refreshToken,
                    expiresAt: reply.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) })
            }
            switch reply.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw AuthorizationFailure.denied
            case "expired_token": throw AuthorizationFailure.expired
            default: throw AuthorizationFailure.notConfigured
            }
        }
        throw AuthorizationFailure.expired
    }

    func refresh(clientID: String, credential: GitHubCredential) async throws -> GitHubCredential {
        guard let refreshToken = credential.refreshToken else { throw AuthorizationFailure.expired }
        let data = try await post("https://github.com/login/oauth/access_token", values: [
            "client_id": clientID, "refresh_token": refreshToken, "grant_type": "refresh_token"
        ])
        let reply = try JSONDecoder().decode(TokenReply.self, from: data)
        guard let token = reply.accessToken, !token.isEmpty else { throw AuthorizationFailure.expired }
        return GitHubCredential(accessToken: token, refreshToken: reply.refreshToken ?? refreshToken,
            expiresAt: reply.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) })
    }

    private func post(_ endpoint: String, values: [String: String]) async throws -> Data {
        var body = URLComponents()
        body.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthorizationFailure.unavailable
        }
        return data
    }

    private struct TokenReply: Decodable {
        let accessToken: String?
        let scope: String?
        let error: String?
        let refreshToken: String?
        let expiresIn: Int?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", scope, error
            case refreshToken = "refresh_token", expiresIn = "expires_in"
        }
    }
}

enum AuthorizationFailure: LocalizedError {
    case notConfigured, expired, denied, unavailable, permissionMissing
    var errorDescription: String? {
        switch self {
        case .notConfigured: "GitHub 授权应用尚未配置，或未启用 Device Flow。"
        case .expired: "授权码已过期，请重新开始登录。"
        case .denied: "你取消了 GitHub 授权。"
        case .unavailable: "暂时无法连接 GitHub 授权服务，请稍后重试。"
        case .permissionMissing: "此次授权未包含公开仓库发布权限，请重新授权。"
        }
    }
}
