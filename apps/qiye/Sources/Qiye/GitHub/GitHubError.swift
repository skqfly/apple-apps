import Foundation

enum GitHubError: LocalizedError, Sendable {
    case signInRequired
    case http(Int, rateLimited: Bool)
    case invalidResponse
    case invalidContent(String)
    case conflict
    case publishUncertain
    case network

    var errorDescription: String? {
        switch self {
        case .signInRequired: return "请先在个人中心连接 GitHub，再发布内容。"
        case let .http(status, rateLimited):
            if rateLimited { return "GitHub 请求次数已达上限，请稍后重试；连接账户后可提高读取额度。" }
            switch status {
            case 401: return "GitHub 登录已失效，请在个人中心重新连接。"
            case 403: return "GitHub 拒绝了操作，请确认账户具有此仓库的内容写入权限。"
            case 404: return "未找到 GitHub 内容，请确认仓库权限和文件路径。"
            case 409, 422: return "仓库内容发生冲突，请刷新后重试。"
            case 500...599: return "GitHub 服务暂时不可用，请稍后重试。"
            default: return "GitHub 请求未完成（\(status)），请稍后重试。"
            }
        case .invalidResponse: return "GitHub 返回的资料格式不完整，请稍后刷新。"
        case let .invalidContent(message): return message
        case .conflict: return "发布时仓库持续有新提交，尚未完成发布。请刷新后重试。"
        case .publishUncertain: return "连接中断，暂时无法确认提交结果。请先刷新列表或查看 GitHub 提交记录，再决定是否重试。"
        case .network: return "暂时无法连接 GitHub，请检查网络后重试。"
        }
    }
}
