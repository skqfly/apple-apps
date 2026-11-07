import Foundation

struct PhotoDraft: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let importedAt: Date
    let filename: String
    let thumbnailFilename: String
    let width: Int
    let height: Int
    var publishedCommit: String? = nil
    var publicationUncertain: Bool? = nil
}

struct PhotoImportResult: Equatable, Sendable {
    let importedCount: Int
    let failedCount: Int
    let failures: [String]

    var message: String {
        if failedCount == 0 { return "已将 \(importedCount) 张照片保存到本机。" }
        return "已导入 \(importedCount) 张，\(failedCount) 张未能导入。\n" + failures.joined(separator: "\n")
    }
}
