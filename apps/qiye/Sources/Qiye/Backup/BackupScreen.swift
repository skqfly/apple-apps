import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BackupScreen: View {
    @State private var showsFolderExporter = false
    @State private var showsImporter = false
    @State private var exportFolderURL: URL?
    @State private var message: String?
    @State private var showsMessage = false
    @State private var isWorking = false

    @AppStorage("webdavURL") private var webdavURL = ""
    @AppStorage("webdavUsername") private var webdavUsername = ""
    @AppStorage("webdavFolderName") private var webdavFolderName = ""
    @State private var webdavPassword = ""

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
                Text("备份是一个文件夹，包含照片与说说等全部数据，可存到 iCloud Drive 或任意位置。恢复后请退出并重新打开栖页。")
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
                TextField("备份文件夹名", text: $webdavFolderName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("WebDAV")
            } footer: {
                Text("密码仅保存在设备钥匙串。上传后会记住文件夹名，下载时使用同一个名字。")
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
        .sheet(isPresented: $showsFolderExporter) {
            if let exportFolderURL {
                FolderExporter(folderURL: exportFolderURL, isPresented: $showsFolderExporter) { error in
                    self.exportFolderURL = nil
                    if let error { report(error.localizedDescription) }
                }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .alert("备份与恢复", isPresented: $showsMessage) {
            Button("好", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Files

    private func exportToFiles() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let folder = try makeTempBackupFolder()
            exportFolderURL = folder
            showsFolderExporter = true
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

    private func makeTempBackupFolder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QiyeBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = directory.appendingPathComponent(folderName(), isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try service.prepareBackupFolder(to: folder)
        return folder
    }

    private func folderName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "栖页备份-\(formatter.string(from: Date()))"
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
            let folder = try makeTempBackupFolder()
            let name = folder.lastPathComponent
            try await service.webDAVUpload(folderURL: folder, folderName: name, to: server)
            webdavFolderName = name
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
            let name = webdavFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw BackupError.noServer }
            let folder = try await service.webDAVDownload(folderName: name, from: server)
            try service.restore(from: folder)
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

/// Exports a directory via the system document picker so the user can save the
/// whole backup folder to iCloud Drive or any Files location.
private struct FolderExporter: UIViewControllerRepresentable {
    let folderURL: URL
    @Binding var isPresented: Bool
    let onCompletion: (Error?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PresenterController {
        PresenterController(folderURL: folderURL, coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: PresenterController, context: Context) {
        controller.folderURL = folderURL
        controller.coordinator = context.coordinator
    }

    final class PresenterController: UIViewController {
        var folderURL: URL
        weak var coordinator: Coordinator?
        private var didPresent = false

        init(folderURL: URL, coordinator: Coordinator) {
            self.folderURL = folderURL
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didPresent else { return }
            didPresent = true
            let picker = UIDocumentPickerViewController(forExporting: [folderURL], asCopy: true)
            picker.delegate = coordinator
            present(picker, animated: false)
        }
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var parent: FolderExporter
        init(_ parent: FolderExporter) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            parent.onCompletion(nil)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
            parent.onCompletion(nil)
        }
    }
}
