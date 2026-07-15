import SwiftUI
import PhotosUI

/// Compose sheet — new thread (with subject) or reply comment. Hosts the bundled
/// Trix editor and posts via the native API.
struct ComposeView: View {
    enum Mode {
        case newThread(board: Board)
        case comment(messageID: Int, subject: String)
        case editThread(message: MessageDetail)
        case editComment(comment: Comment)
        case editChat(line: ChatLine)
    }

    let mode: Mode
    var onPosted: (Int) -> Void          // new message id or comment id

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var model = ComposerModel()
    @State private var subject = ""
    @State private var categoryID = 0
    @State private var posting = false
    @State private var error: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false

    private let api = DcampAPI.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isNewThread {
                    TextField("Subject", text: $subject)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    if !boardCategories.isEmpty {
                        Divider()
                        Picker("Category", selection: $categoryID) {
                            Text("No category").tag(0)
                            ForEach(boardCategories) { c in Text(c.name).tag(c.id) }
                        }
                        .padding(.horizontal, 10)
                    }
                    Divider()
                }
                ComposerWebView(model: model)
                    .overlay(alignment: .top) { MentionOverlay(model: model).padding(.top, 52).padding(.horizontal, 8) }
                    .overlay(alignment: .bottom) { if uploading { uploadingBar } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) { EmptyView() }
                ToolbarItem(placement: .primaryAction) {
                    if posting { ProgressView() }
                    else { Button("Post", action: post).fontWeight(.semibold).disabled(!canPost) }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo")
                    }
                    Spacer()
                }
            }
            .alert("Couldn’t post", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onChange(of: photoItem) { _, item in
                if let item { Task { await attach(item) } }
            }
            .task {
                if case .editThread(let m) = mode, subject.isEmpty { subject = m.displaySubject }
                // Wait for the editor, preload existing content for edit modes, focus.
                for _ in 0..<30 { if model.ready { break }; try? await Task.sleep(nanoseconds: 120_000_000) }
                if let editHTML { model.loadHTML(editHTML) }
                model.focus()
            }
        }
    }

    private var isNewThread: Bool {
        switch mode { case .newThread, .editThread: return true; default: return false }
    }

    private var title: String {
        switch mode {
        case .newThread(let b): return b.name
        case .comment: return "Reply"
        case .editThread: return "Edit"
        case .editComment: return "Edit comment"
        case .editChat: return "Edit message"
        }
    }

    private var boardCategories: [Category] {
        let pid: Int?
        switch mode {
        case .newThread(let b): pid = b.id
        case .editThread(let m): pid = m.projectId
        default: return []
        }
        return session.categories.filter { ($0.projectId ?? 0) == 0 || $0.projectId == pid }
    }

    /// Existing HTML to preload for edit modes.
    private var editHTML: String? {
        switch mode {
        case .editThread(let m): return m.html
        case .editComment(let c): return c.html
        case .editChat(let l): return l.html
        default: return nil
        }
    }

    private var canPost: Bool {
        guard !posting else { return false }
        if isNewThread { return !subject.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var uploadingBar: some View {
        HStack { ProgressView(); Text("Uploading image…").font(.caption) }
            .padding(8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
    }

    private func attach(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let url = try await api.uploadImage(data, filename: "image.\(ext)", mime: mime)
            // Insert absolute for the in-editor preview; post() strips the host
            // back to a relative path so stored HTML matches the web app.
            model.insertImage(absoluteURL: AppConfig.assetBase + url)
        } catch {
            self.error = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
        }
    }

    private func post() {
        posting = true
        Task {
            defer { posting = false }
            // Read the editor's content on demand and normalize image URLs back to
            // host-relative (as the SPA stores them).
            let html = await model.currentHTML().replacingOccurrences(of: AppConfig.assetBase, with: "")
            if PlainText.strip(html).isEmpty {
                error = "Write something before posting."
                return
            }
            do {
                switch mode {
                case .newThread(let board):
                    let r = try await api.createMessage(projectID: board.id, categoryID: categoryID,
                                                        subject: subject.trimmingCharacters(in: .whitespaces),
                                                        bodyHTML: html)
                    guard let id = r.id else { throw DcampAPI.APIError(message: r.error ?? "Failed", code: r.code) }
                    onPosted(id); dismiss()
                case .comment(let messageID, _):
                    let r = try await api.createComment(messageID: messageID, bodyHTML: html)
                    guard let id = r.id else { throw DcampAPI.APIError(message: r.error ?? "Failed", code: r.code) }
                    onPosted(id); dismiss()
                case .editThread(let m):
                    try await api.messageUpdate(id: m.id, categoryID: m.categoryId ?? 0,
                                                subject: subject.trimmingCharacters(in: .whitespaces), bodyHTML: html)
                    onPosted(m.id); dismiss()
                case .editComment(let c):
                    try await api.commentUpdate(id: c.id, bodyHTML: html)
                    onPosted(c.id); dismiss()
                case .editChat(let l):
                    try await api.chatUpdate(id: l.id, bodyHTML: html)
                    onPosted(l.id); dismiss()
                }
            } catch {
                self.error = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
            }
        }
    }
}
