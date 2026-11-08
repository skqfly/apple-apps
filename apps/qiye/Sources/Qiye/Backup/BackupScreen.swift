import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BackupScreen: View {
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var exportDocument: BackupDocument?
    @State private var message: String?
    @State private var showsMessage = false
    @State private var isWorking = false

    @AppStorage("webdavURL") private var webdavURL = ""
    @AppStorage("webdavUsername") private var webdavUsername = ""
    @State private var webdavPassword = ""
    @State private var webdavDownloadName = ""

    private let keychain = WebDAVKeychain()
    private let service = BackupService()

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await exportToFiles() }
                } label: {
                    Label("导出备份到文件", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking)
                Button {
                    showsImporter = true
                } label: {
                    Label("从文件恢复备份", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)
            } header: {
                Text("iCloud Drive / 文件")
            } footer: {
                Text("备份会打包成单个文件，可存到 iCloud Drive 或任意位置。恢复后请退出并重新打开栖页。")
            }

            Section {
                TextField("https://dav.example.com/dav/", text: $webdavURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("用户名", text: $webdavUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $webdavPassword)
                TextField("下载文件名（可选）", text: $webdavDownloadName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("WebDAV")
            } footer: {
                Text("密码仅保存在设备钥匙串。上传后会自动记录一个默认文件名，下载时留空则使用最近一次备份名。")
            }

            Section {
                Button {
                    Task { await uploadToWebDAV() }
                } label: {
                    Label("上传备份到 WebDAV", systemImage: "arrow.up.circle")
                }
                .disabled(isWorking)
                Button {
                    Task { await downloadFromWebDAV() }
                } label: {
                    Label("从 WebDAV 下载并恢复", systemImage: "arrow.down.circle")
                }
                .disabled(isWorking)
            }

            if isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在处理…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .task { webdavPassword = keychain.read() ?? "" }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .data,
            defaultFilename: defaultFilename()
        ) { result in
            exportDocument = nil
            if case .failure(let error) = result {
                report(error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .alert("备份与恢复", isPresented: $showsMessage) {
            Button("好", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
        .disabled(isWorking)
    }

    // MARK: - Files

    private func exportToFiles() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let archive = try makeTempArchive()
            let data = try Data(contentsOf: archive)
            exportDocument = BackupDocument(data: data)
            showsExporter = true
        } catch {
            report(error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try service.restore(from: url)
                report("已恢复。请退出并重新打开栖页让数据生效。")
            case .failure(let error):
                report(error.localizedDescription)
            }
        } catch {
            report(error.localizedDescription)
        }
    }

    private func makeTempArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QiyeBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(defaultFilename())
        try? FileManager.default.removeItem(at: url)
        try service.makeArchive(to: url)
        return url
    }

    private func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "栖页备份-\(formatter.string(from: Date())).qibackup"
    }

    // MARK: - WebDAV

    private func currentServer() throws -> WebDAVServer {
        let trimmed = webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw BackupError.invalidServerURL
        }
        guard !webdavUsername.isEmpty, !webdavPassword.isEmpty else {
            throw BackupError.noServer
        }
        return WebDAVServer(baseURL: url, username: webdavUsername, password: webdavPassword)
    }

    private func uploadToWebDAV() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let server = try currentServer()
            keychain.save(webdavPassword)
            let archive = try makeTempArchive()
            try await service.webDAVUpload(archive, to: server)
            webdavDownloadName = archive.lastPathComponent
            report("已上传到 WebDAV。")
        } catch {
            report(error.localizedDescription)
        }
    }

    private func downloadFromWebDAV() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let server = try currentServer()
            keychain.save(webdavPassword)
            let name = webdavDownloadName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw BackupError.noServer }
            let data = try await service.webDAVDownload(name, from: server)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QiyeBackups", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let archive = directory.appendingPathComponent(name)
            try data.write(to: archive, options: .atomic)
            try service.restore(from: archive)
            report("已下载并恢复。请退出并重新打开栖页让数据生效。")
        } catch {
            report(error.localizedDescription)
        }
    }

    private func report(_ text: String) {
        message = text
        showsMessage = true
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
