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
    @ObservationIgnored private var accessToken: String?

    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentToken() -> String? { isSignedIn ? accessToken : nil }

    func restore() async {
        guard !didAttemptRestore, !isLoading else { return }
        didAttemptRestore = true
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        guard !isLoading else { return }
        let id = UUID()
        operationID = id
        isLoading = true
        defer { if operationID == id { isLoading = false } }
        do {
            guard var credential = try keychain.readCredential() else { return }
            if credential.needsRefresh {
                credential = try await authorization.refresh(clientID: clientID, credential: credential)
                guard operationID == id else { return }
                try keychain.saveCredential(credential)
            }
            let account = try await validate(credential.accessToken)
            try Task.checkCancellation()
            guard operationID == id else { return }
            accept(account, token: credential.accessToken)
        } catch is CancellationError { return
        } catch let failure as URLError where failure.code == .cancelled { return
        } catch {
            guard operationID == id else { return }
            self.error = userMessage(error)
            didAttemptRestore = false
            if error is AuthorizationFailure {
                accessToken = nil
                isSignedIn = false
                credentialRevision += 1
            }
        }
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
                let account = try await validate(credential.accessToken)
                try Task.checkCancellation()
                guard operationID == id else { return }
                try keychain.saveCredential(credential)
                accept(account, token: credential.accessToken)
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

    private func accept(_ account: GitHubAccount, token: String) {
        name = account.name.flatMap { $0.isEmpty ? nil : $0 } ?? account.login
        avatarURL = account.avatarURL
        accessToken = token
        isSignedIn = true
        didAttemptRestore = true
        error = nil
        credentialRevision += 1
    }

    private func validate(_ token: String) async throws -> GitHubAccount {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthorizationFailure.expired }
        let account = try JSONDecoder().decode(GitHubAccount.self, from: data)
        guard account.login.caseInsensitiveCompare(Self.administratorLogin) == .orderedSame else {
            throw AccountFailure.wrongAccount
        }
        return account
    }

    private func userMessage(_ failure: Error) -> String {
        if let error = failure as? AuthorizationFailure { return error.localizedDescription }
        if failure is AccountFailure { return "请使用 skqfly 的 GitHub 账户登录。" }
        if failure is AccountTokenKeychain.StorageError { return "无法访问设备钥匙串，请解锁后重试。" }
        return "无法连接 GitHub，请检查网络后重试。"
    }

    private enum AccountFailure: Error { case wrongAccount }
}
