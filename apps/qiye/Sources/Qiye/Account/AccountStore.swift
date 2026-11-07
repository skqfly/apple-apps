import Foundation
import Observation

@Observable @MainActor
final class AccountStore {
    static let administratorLogin = "skqfly"
    private(set) var name = ""
    private(set) var avatarURL: URL?
    private(set) var isSignedIn = false
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var deviceCode: GitHubDeviceCode?
    private(set) var credentialRevision = 0
    @ObservationIgnored private let keychain = AccountTokenKeychain()
    @ObservationIgnored private let authorization = GitHubDeviceAuthorization()
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored private var explicitlySignedOut = false
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiresAt: Date?

    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentToken() -> String? {
        guard isSignedIn, accessTokenExpiresAt.map({ $0 > Date() }) ?? true else { return nil }
        return accessToken
    }

    func restore() async {
        guard !didAttemptRestore, !isLoading else { return }
        didAttemptRestore = true
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        guard !isLoading, !explicitlySignedOut else { return }
        let id = UUID()
        operationID = id
        isLoading = true
        defer { if operationID == id { isLoading = false } }
        do {
            guard var credential = try keychain.readCredential() else { return }
            if credential.needsRefresh {
                credential = try await authorization.refresh(clientID: clientID, credential: credential)
                try Task.checkCancellation()
                guard operationID == id else { return }
                try keychain.saveCredential(credential)
            }
            let account = try await validate(credential.accessToken)
            try Task.checkCancellation()
            guard operationID == id else { return }
            accept(account, credential: credential)
        } catch is CancellationError { return
        } catch let failure as URLError where failure.code == .cancelled { return
        } catch {
            guard operationID == id else { return }
            self.error = userMessage(error)
            didAttemptRestore = false
            let invalidAuthorization: Bool
            if let failure = error as? AuthorizationFailure {
                switch failure {
                case .expired, .denied, .permissionMissing: invalidAuthorization = true
                case .notConfigured, .unavailable: invalidAuthorization = false
                }
            } else { invalidAuthorization = error is AccountFailure }
            if invalidAuthorization {
                accessToken = nil
                isSignedIn = false
                name = ""
                avatarURL = nil
                credentialRevision += 1
            }
        }
    }

    @discardableResult
    func signIn(token input: String) async -> Bool {
        guard !isLoading else { return false }
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            error = "请输入有效的 GitHub token。"
            return false
        }
        let id = UUID()
        operationID = id
        error = nil
        isLoading = true
        defer { if operationID == id { isLoading = false } }
        do {
            let account = try await validate(token)
            try await validateRepositoryAccess(token)
            try Task.checkCancellation()
            guard operationID == id else { return false }
            let credential = GitHubCredential(accessToken: token, refreshToken: nil, expiresAt: nil)
            try keychain.saveCredential(credential)
            accept(account, credential: credential)
            return true
        } catch is CancellationError { return false
        } catch {
            guard operationID == id else { return false }
            self.error = userMessage(error)
            return false
        }
    }

    private func validateRepositoryAccess(_ token: String) async throws {
        struct RepositoryAccess: Decodable {
            struct Permissions: Decodable { let push: Bool? }
            let permissions: Permissions?
        }
        let data = try await authorizedData("https://api.github.com/repos/skqfly/skqfly.github.io", token: token)
        let repository = try JSONDecoder().decode(RepositoryAccess.self, from: data)
        guard repository.permissions?.push == true else { throw AccountFailure.noRepositoryAccess }
    }

    func beginGitHubLogin() {
        guard !isLoading, !clientID.isEmpty else { return }
        let id = UUID()
        operationID = id
        error = nil
        isLoading = true
        authorizationTask = Task {
            defer {
                if operationID == id { isLoading = false; deviceCode = nil }
            }
            do {
                let code = try await authorization.start(clientID: clientID)
                try Task.checkCancellation()
                guard operationID == id else { return }
                deviceCode = code
                let credential = try await authorization.waitForToken(clientID: clientID, code: code)
                try Task.checkCancellation()
                guard operationID == id else { return }
                let account = try await validate(credential.accessToken)
                try Task.checkCancellation()
                guard operationID == id else { return }
                try keychain.saveCredential(credential)
                accept(account, credential: credential)
            } catch is CancellationError { return
            } catch {
                guard operationID == id else { return }
                self.error = userMessage(error)
            }
        }
    }

    func cancelGitHubLogin() {
        operationID = UUID()
        authorizationTask?.cancel()
        authorizationTask = nil
        deviceCode = nil
        isLoading = false
    }

    func logout() {
        cancelGitHubLogin()
        explicitlySignedOut = true
        accessToken = nil
        isSignedIn = false
        name = ""
        avatarURL = nil
        error = nil
        credentialRevision += 1
        didAttemptRestore = true
        do { try keychain.delete() }
        catch { self.error = "未能清除设备钥匙串，请解锁设备后重试。" }
    }

    private func accept(_ account: GitHubAccount, credential: GitHubCredential) {
        explicitlySignedOut = false
        name = account.name.flatMap { $0.isEmpty ? nil : $0 } ?? account.login
        avatarURL = account.avatarURL
        accessToken = credential.accessToken
        accessTokenExpiresAt = credential.expiresAt
        isSignedIn = true
        didAttemptRestore = true
        error = nil
        credentialRevision += 1
    }

    private func validate(_ token: String) async throws -> GitHubAccount {
        let data = try await authorizedData("https://api.github.com/user", token: token)
        let account = try JSONDecoder().decode(GitHubAccount.self, from: data)
        guard account.login.caseInsensitiveCompare(Self.administratorLogin) == .orderedSame else {
            throw AccountFailure.wrongAccount
        }
        return account
    }

    private func authorizedData(_ address: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AuthorizationFailure.unavailable }
        if http.statusCode == 401 { throw AuthorizationFailure.expired }
        if http.statusCode == 403 { throw AccountFailure.permissionDenied }
        if http.statusCode == 404 { throw AccountFailure.noRepositoryAccess }
        guard http.statusCode == 200 else { throw AuthorizationFailure.unavailable }
        return data
    }

    private func userMessage(_ failure: Error) -> String {
        if let error = failure as? AuthorizationFailure { return error.localizedDescription }
        if let accountFailure = failure as? AccountFailure {
            switch accountFailure {
            case .wrongAccount: return "请使用 skqfly 的 GitHub 账户登录。"
            case .noRepositoryAccess: return "token 无法访问网站仓库，请选择 skqfly.github.io 并授予 Contents 读写权限。"
            case .permissionDenied: return "GitHub 拒绝访问，请检查 token 权限或稍后重试。"
            }
        }
        if let network = failure as? URLError {
            switch network.code {
            case .timedOut: return "连接 GitHub API 超时，请确认当前网络或代理可访问 api.github.com。"
            case .notConnectedToInternet, .networkConnectionLost: return "网络已断开，请连接网络后重试。"
            case .cannotFindHost, .dnsLookupFailed: return "无法解析 GitHub API 地址，请检查网络或 DNS。"
            case .secureConnectionFailed, .serverCertificateUntrusted: return "无法与 GitHub API 建立安全连接，请检查代理或系统时间。"
            default: break
            }
        }
        if failure is AccountTokenKeychain.StorageError { return "无法访问设备钥匙串，请解锁后重试。" }
        return "无法连接 GitHub，请检查网络后重试。"
    }

    private enum AccountFailure: Error { case wrongAccount, noRepositoryAccess, permissionDenied }
}
