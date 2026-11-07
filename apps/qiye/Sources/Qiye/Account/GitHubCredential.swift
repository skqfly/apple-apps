import Foundation

struct GitHubCredential: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let refreshExpiresAt: Date?

    init(accessToken: String, refreshToken: String?, expiresAt: Date?, refreshExpiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    var needsRefresh: Bool {
        expiresAt.map { $0.timeIntervalSinceNow < (refreshToken == nil ? 0 : 120) } ?? false
    }
}
