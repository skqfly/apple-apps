import Foundation

struct GitHubCredential: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var needsRefresh: Bool {
        expiresAt.map { $0.timeIntervalSinceNow < 120 } ?? false
    }
}
