import SwiftUI

@MainActor
struct TrashScreen: View {
    let library: ContentLibraryStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: TrashFilter = .all
    @State private var confirmsPurgeAll = false
    @State private var photoToPurge: WebsitePhoto?
    @State private var talkToPurge: TalkPost?
    @State private var viewingPhoto: PhotoSelection?
    @State private var notice: String?

    enum TrashFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case photos = "照片"
        case talks = "说说"
        var id: String { rawValue }
    }

    private var deletedPhotos: [WebsitePhoto] {
        library.photos(in: .deleted)
    }

    private var deletedTalks: [TalkPost] {
        library.talks(in: .deleted)
    }

    private var totalCount: Int {
        deletedPhotos.count + deletedTalks.count
    }

    private var filteredPhotos: [WebsitePhoto] {
        filter == .talks ? [] : deletedPhotos
    }

    private var filteredTalks: [TalkPost] {
        filter == .photos ? [] : deletedTalks
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 8)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let notice {
                    Text(notice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .liquidGlassCapsule(interactive: false)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Filter Pill Bar
                filterBar

                if totalCount == 0 {
                    emptyState
                } else {
                    contentSections
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.appBackground)
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if totalCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        Haptics.medium()
                        confirmsPurgeAll = true
                    } label: {
                        Text("清空")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog("确定清空回收站？", isPresented: $confirmsPurgeAll, titleVisibility: .visible) {
            Button("清空全部内容", role: .destructive) {
                purgeAll()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将彻底删除回收站里的 \(totalCount) 项内容，此操作无法撤销。")
        }
        .confirmationDialog("彻底删除这张照片？", isPresented: Binding(get: { photoToPurge != nil }, set: { if !$0 { photoToPurge = nil } }), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) {
                if let photo = photoToPurge {
                    purge(photo: photo)
                }
                photoToPurge = nil
            }
        } message: {
            Text("照片将从本地永久抹除，无法再恢复。")
        }
        .confirmationDialog("彻底删除这条说说？", isPresented: Binding(get: { talkToPurge != nil }, set: { if !$0 { talkToPurge = nil } }), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) {
                if let talk = talkToPurge {
                    purge(talk: talk)
                }
                talkToPurge = nil
            }
        } message: {
            Text("说说及其本地图片将永久抹除，无法再恢复。")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(TrashFilter.allCases) { item in
                let isSelected = filter == item
                let count = count(for: item)
                Button {
                    Haptics.selection()
                    withAnimation(.snappy(duration: 0.2)) {
                        filter = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.rawValue)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        Text("\(count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(
                                    isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12)
                                )
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.appAccent)
                        } else {
                            Capsule().fill(Color.secondary.opacity(0.10))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func count(for item: TrashFilter) -> Int {
        switch item {
        case .all: return totalCount
        case .photos: return deletedPhotos.count
        case .talks: return deletedTalks.count
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.slash")
                .font(.system(size: 46))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.top, 40)

            Text("回收站是空的")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("在照片墙或说说流中移到回收站的内容，会安全保留在这里，随时可以找回或清空。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        if !filteredPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("已删除照片 (\(filteredPhotos.count))", systemImage: "photo.stack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredPhotos) { photo in
                        photoCell(photo)
                    }
                }
            }
            .padding(.top, 4)
        }

        if !filteredTalks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("已删除说说 (\(filteredTalks.count))", systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                LazyVStack(spacing: 12) {
                    ForEach(filteredTalks) { talk in
                        talkCard(talk)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Photo Cell

    private func photoCell(_ photo: WebsitePhoto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(0.88, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        if let local = library.localPreviewURL(for: photo.id) {
                            LocalPhotoImage(url: local)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            RemotePhotoImage(url: photo.preview, allowsRetry: false)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    }
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(0.88)

            HStack(spacing: 6) {
                Button {
                    Haptics.selection()
                    restore(photo: photo)
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.appAccent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    photoToPurge = photo
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .liquidGlassCard(cornerRadius: 14)
    }

    // MARK: - Talk Card

    private func talkCard(_ talk: TalkPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if !talk.description.isEmpty {
                        Text(talk.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }

                    Text(talk.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button {
                        Haptics.selection()
                        restore(talk: talk)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("恢复")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appAccent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.light()
                        talkToPurge = talk
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !talk.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(talk.images.prefix(4).enumerated()), id: \.offset) { _, img in
                        if let url = img.url {
                            Color.clear
                                .frame(width: 48, height: 48)
                                .overlay {
                                    if url.isFileURL {
                                        LocalPhotoImage(url: url)
                                            .scaledToFill()
                                    } else {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Color.secondary.opacity(0.15)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
        .opacity(0.88)
    }

    // MARK: - Actions

    private func restore(photo: WebsitePhoto) {
        do {
            try library.restorePhoto(photo)
            showNotice("照片已恢复到「已下架」，可在照片页查看")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func restore(talk: TalkPost) {
        do {
            try library.restoreTalk(talk)
            showNotice("说说已恢复到「未发表」")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func purge(photo: WebsitePhoto) {
        do {
            try library.purgePhoto(photo)
            showNotice("照片已彻底删除")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func purge(talk: TalkPost) {
        do {
            try library.purgeTalk(talk)
            showNotice("说说已彻底删除")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func purgeAll() {
        let count = totalCount
        for p in deletedPhotos { try? library.purgePhoto(p) }
        for t in deletedTalks { try? library.purgeTalk(t) }
        Haptics.success()
        showNotice("已清空回收站全部 \(count) 项内容")
    }

    private func showNotice(_ text: String) {
        withAnimation(.snappy(duration: 0.25)) { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) {
                if notice == text { notice = nil }
            }
        }
    }
}
