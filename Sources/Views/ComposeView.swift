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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var posted = false
    @State private var precheckPassed = false
    @State private var showSubjectSheet = false
    @State private var suggestedSubject = ""
    @State private var showDerekSheet = false
    @State private var derekHTML = ""

    private let api = DcampAPI.shared

    /// Draft-persistence key — only new-thread / comment composing keeps a draft
    /// (edit modes are pre-loaded with the existing content).
    private var draftKey: String? {
        switch mode {
        case .newThread(let b): return "new:\(b.id)"
        case .comment(let mid, _): return "comment:\(mid)"
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isNewThread {
                    TextField(T("Subject"), text: $subject)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    if !boardCategories.isEmpty {
                        Divider()
                        Picker(T("Category"), selection: $categoryID) {
                            Text(T("No category")).tag(0)
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
                    Button(T("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .principal) { EmptyView() }
                ToolbarItem(placement: .primaryAction) {
                    if posting { ProgressView() }
                    else { Button(T("Post"), action: post).fontWeight(.semibold).disabled(!canPost) }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    Spacer()
                }
            }
            .alert(T("Couldn’t post"), isPresented: .constant(error != nil)) {
                Button(T("OK")) { error = nil }
            } message: { Text(error ?? "") }
            .sheet(isPresented: $showSubjectSheet) {
                SubjectSuggestionSheet(current: subject, suggested: suggestedSubject) { useSuggested in
                    if useSuggested { subject = suggestedSubject }
                    showSubjectSheet = false; precheckPassed = true; doPost()
                }
            }
            .sheet(isPresented: $showDerekSheet) {
                PreAnswerSheet(html: derekHTML, onRoute: nil) { postAnyway in
                    showDerekSheet = false
                    if postAnyway { precheckPassed = true; doPost() }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                let picked = items; photoItems = []
                Task { await attachMany(picked) }
            }
            .onChange(of: model.submitRequested) { _, _ in if canPost { post() } }   // ⌘↵
            .onDisappear { if !posted { Task { await model.saveDraft() } } }
            .task {
                if case .editThread(let m) = mode, subject.isEmpty { subject = m.displaySubject }
                // Wait for the editor, preload existing content for edit modes, focus.
                for _ in 0..<30 { if model.ready { break }; try? await Task.sleep(nanoseconds: 120_000_000) }
                model.draftKey = draftKey
                if let editHTML { model.loadHTML(editHTML) }
                else { model.loadDraft() }
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
        HStack { ProgressView(); Text(T("Uploading image…")).font(.caption) }
            .padding(8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
    }

    private func attachMany(_ items: [PhotosPickerItem]) async {
        uploading = true
        defer { uploading = false }
        for item in items { await attachOne(item) }
    }

    private func attachOne(_ item: PhotosPickerItem) async {
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

    /// Mark a successful post so the draft is dropped and not re-saved on dismiss.
    private func markPosted() { posted = true; model.clearDraft() }

    /// New-thread posts run two AI pre-checks first (clearer-subject suggestion, then
    /// "Derek may already have an answer" for question-like posts). Everything else posts directly.
    private func post() {
        guard isNewThread, !precheckPassed else { doPost(); return }
        posting = true
        Task {
            let html = await model.currentHTML().replacingOccurrences(of: AppConfig.assetBase, with: "")
            let subj = subject.trimmingCharacters(in: .whitespaces)
            if PlainText.strip(html).isEmpty { posting = false; error = "Write something before posting."; return }
            let sc = await api.subjectCheck(subject: subj, body: html)
            if !sc.isGood, let s = sc.suggestion, !s.isEmpty {
                suggestedSubject = s; showSubjectSheet = true; posting = false; return
            }
            if looksLikeQuestion(subj: subj, body: html) {
                let pa = await api.preAnswer(subject: subj, body: html)
                if pa.has, let a = pa.answer, !a.isEmpty { derekHTML = a; showDerekSheet = true; posting = false; return }
            }
            precheckPassed = true
            doPost()
        }
    }

    private func looksLikeQuestion(subj: String, body: String) -> Bool {
        if case .newThread(let b) = mode, b.name == "Problems" { return true }
        return subj.contains("?") || PlainText.strip(body).contains("?")
    }

    private func doPost() {
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
                    markPosted(); onPosted(id); dismiss()
                case .comment(let messageID, _):
                    let r = try await api.createComment(messageID: messageID, bodyHTML: html)
                    guard let id = r.id else { throw DcampAPI.APIError(message: r.error ?? "Failed", code: r.code) }
                    markPosted(); onPosted(id); dismiss()
                case .editThread(let m):
                    try await api.messageUpdate(id: m.id, categoryID: m.categoryId ?? 0,
                                                subject: subject.trimmingCharacters(in: .whitespaces), bodyHTML: html)
                    markPosted(); onPosted(m.id); dismiss()
                case .editComment(let c):
                    try await api.commentUpdate(id: c.id, bodyHTML: html)
                    markPosted(); onPosted(c.id); dismiss()
                case .editChat(let l):
                    try await api.chatUpdate(id: l.id, bodyHTML: html)
                    markPosted(); onPosted(l.id); dismiss()
                }
            } catch {
                self.error = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
            }
        }
    }
}

/// "Clearer subject?" pre-post sheet (from `subject_check`).
struct SubjectSuggestionSheet: View {
    let current: String
    let suggested: String
    var onDecision: (Bool) -> Void          // true = use the suggested subject

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(T("A clearer subject helps people find and answer your post."))
                    .font(.system(size: 15)).foregroundStyle(Color.dcInkSoft)
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("YOUR SUBJECT")).font(.caption).foregroundStyle(Color.dcMuted)
                    Text(current).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.dcInk)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("SUGGESTED")).font(.caption).foregroundStyle(Color.dcAccentInk)
                    Text(suggested).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.dcInk)
                }
                Spacer()
                Button(T("Use suggested subject")) { onDecision(true) }
                    .buttonStyle(DCPrimaryButtonStyle()).frame(maxWidth: .infinity)
                Button(T("Keep mine")) { onDecision(false) }.frame(maxWidth: .infinity)
            }
            .padding(20)
            .navigationTitle(T("Clearer subject?")).navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

/// "Derek may already have an answer" pre-post sheet (from `pre_answer`).
struct PreAnswerSheet: View {
    let html: String
    var onRoute: ((String) -> Void)?
    var onDecision: (Bool) -> Void          // true = post anyway

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(Color.dcAccent)
                        Text(T("Derek may already have an answer"))
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.dcInk)
                    }
                    TrixContentView(html: html, onRoute: onRoute).font(.system(size: 15))
                }.padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(T("Let me reconsider")) { onDecision(false) }.frame(maxWidth: .infinity)
                    Button(T("Post anyway")) { onDecision(true) }
                        .buttonStyle(DCPrimaryButtonStyle()).frame(maxWidth: .infinity)
                }.padding(16).background(.regularMaterial)
            }
            .navigationTitle(T("Before you post")).navigationBarTitleDisplayMode(.inline)
        }
    }
}
