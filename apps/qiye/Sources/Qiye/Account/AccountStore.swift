import Foundation
import Observation

@Observable
@MainActor
final class AccountStore {
    static let administratorLogin = "skqfly"

    private(set) var name = ""
    private(set) var avatarURL: URL?
    private(set) var isSignedIn = false
    private(set) var error: String?
    private(set) var isLoading = false

    @ObservationIgnored private let keychain = AccountTokenKeychain()
    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored private var operationID = UUID()

    /// Call from the root's `.task`. Repeated calls are safe, including from the sheet.
    /// A cached token alone never marks the user as signed in.
    func restore() async {
        guard !didAttemptRestore, !isLoading, !isSignedIn else { return }
        didAttemptRestore = true
        let id = beginOperation()
        defer { finishOperation(id) }

        do {
            guard let token = try keychain.read() else { return }
            let account = try await validate(token)
            try Task.checkCancellation()
            guard operationID == id else { return }
            accept(account)
        } catch is CancellationError {
            if operationID == id { didAttemptRestore = false }
        } catch let networkError as URLError where networkError.code == .cancelled {
            if operationID == id { didAttemptRestore = false }
        } catch {
            guard operationID == id else { return }
            if let failure = error as? ValidationError,
               failure == .unauthorized || failure == .wrongAccount {
                do {
                    try keychain.delete()
                } catch {
                    self.error = "登录凭证已失效，但未能删除钥匙串中的令牌。请点按“清除本机登录凭证”重试。"
                    return
                }
            }
            self.error = message(for: error)
            didAttemptRestore = false
        }
    }

    /// Returns true only after GitHub validation AND successful Keychain storage.
    @discardableResult
    func signIn(token input: String) async -> Bool {
        guard !isLoading, !isSignedIn else { return false }
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            error = "请输入有效的 GitHub Personal Access Token。"
            return false
        }

        let id = beginOperation()
        defer { finishOperation(id) }
        do {
            let account = try await validate(token)
            try Task.checkCancellation()
            guard operationID == id else { return false }
            try keychain.save(token)
            didAttemptRestore = true
            accept(account)
            return true
        } catch is CancellationError {
            return false
        } catch let networkError as URLError where networkError.code == .cancelled {
            return false
        } catch {
            guard operationID == id else { return false }
            self.error = message(for: error)
            return false
        }
    }

    /// Invalidates in-flight results before removing the local token.
    /// Deletion errors remain visible so the UI never claims the token was removed.
    func logout() {
        operationID = UUID()
        isLoading = false
        isSignedIn = false
        name = ""
        avatarURL = nil
        didAttemptRestore = true
        error = nil
        do {
            try keychain.delete()
        } catch {
            self.error = "未能删除钥匙串中的令牌。请在设备解锁后点按“清除本机登录凭证”重试。"
        }
    }

    private func beginOperation() -> UUID {
        let id = UUID()
        operationID = id
        error = nil
        isLoading = true
        return id
    }

    private func finishOperation(_ id: UUID) {
        if operationID == id { isLoading = false }
    }

    private func accept(_ account: GitHubAccount) {
        let displayName = account.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        name = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? account.login
        avatarURL = account.avatarURL?.scheme == "https" ? account.avatarURL : nil
        isSignedIn = true
        error = nil
    }

    private func validate(_ token: String) async throws -> GitHubAccount {
        guard let url = URL(string: "https://api.github.com/user") else {
            throw ValidationError.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Qiye-iOS", forHTTPHeaderField: "User-Agent")

        // An ephemeral session prevents credential-bearing requests entering a disk cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ValidationError.invalidResponse
        }
        switch response.statusCode {
        case 200: break
        case 401: throw ValidationError.unauthorized
        case 403, 429: throw ValidationError.restricted
        case 500...599: throw ValidationError.unavailable
        default: throw ValidationError.invalidResponse
        }
        guard let account = try? JSONDecoder().decode(GitHubAccount.self, from: data) else {
            throw ValidationError.invalidResponse
        }
        guard account.login.caseInsensitiveCompare(Self.administratorLogin) == .orderedSame else {
            throw ValidationError.wrongAccount
        }
        return account
    }

    // Never surface a raw response, request, token, or underlying error description.
    private func message(for error: Error) -> String {
        if error is AccountTokenKeychain.StorageError {
            return "无法访问设备钥匙串，登录信息未能保存或读取。请解锁设备后重试。"
        }
        if let failure = error as? ValidationError {
            switch failure {
            case .unauthorized:
                return "GitHub 拒绝了此令牌，可能已过期或被撤销。请创建新令牌后重试。"
            case .wrongAccount:
                return "此 GitHub 账户无权登录栖页。仅支持 skqfly，请使用该账户创建的令牌。"
            case .restricted:
                return "GitHub 暂时限制了此请求，请检查令牌状态或稍后重试。"
            case .unavailable:
                return "GitHub 服务暂时不可用，请稍后重试。"
            case .invalidResponse:
                return "未能读取 GitHub 身份信息，请稍后重试。"
            }
        }
        return "无法连接 GitHub，身份尚未验证。请检查网络后重试。"
    }

    private enum ValidationError: Error, Equatable {
        case unauthorized, wrongAccount, restricted, unavailable, invalidResponse
    }
}
