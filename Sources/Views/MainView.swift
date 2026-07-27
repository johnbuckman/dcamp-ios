import SwiftUI
import Combine

struct PersonRef: Identifiable { let id: Int }

/// Navigation destinations for the single-column stack (mirrors the web app,
/// which is one centered column with a persistent top bar — not master/detail).
enum Dest: Hashable { case board(Int), thread(Int), chat, dms, dm(Int), search, find }

/// App shell: a `NavigationStack` over the warm-paper forums home, matching the
/// dcamp web layout. Notifications + account live in the top bar.
struct MainView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(UIStrings.self) private var strings
    @Environment(SummaryPin.self) private var summaryPin
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var path: [Dest] = []
    @State private var showAccount = false
    @State private var showNotifs = false
    @State private var notifStore = NotificationsStore()
    @State private var toastNotif: Notif?
    @State private var lastNotifCount = -1
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 0) {
            if hSize == .regular && summaryPin.visible {
                SummarySidebarView().frame(width: 340)
                Divider()
            }
            stack
        }
        .tint(Color.dcAccent)
        .overlay(alignment: .top) {
            if let n = toastNotif {
                NotifToast(notif: n) { openNotif(n) }
                    .padding(.horizontal, 12).padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toastNotif?.id)
        .onChange(of: notifStore.items.count) { _, new in
            // Toast the newest notification when the unread list grows mid-session.
            if lastNotifCount >= 0, new > lastNotifCount, let newest = notifStore.items.max(by: { $0.id < $1.id }) {
                toastNotif = newest
                let id = newest.id
                Task { try? await Task.sleep(nanoseconds: 4_000_000_000); if toastNotif?.id == id { toastNotif = nil } }
            }
            lastNotifCount = new
        }
        // Settings is a full-screen page (like the web), not a small window overlay.
        .fullScreenCover(isPresented: $showAccount) { SettingsView().environment(session).environment(router) }
        .sheet(isPresented: $showNotifs) {
            NotificationsView(store: notifStore) { router.threadID = $0 }
                .environment(session).environment(router)
        }
        .sheet(item: personSheet) { ref in
            PersonCardView(personID: ref.id).environment(session).environment(router)
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .task { await startLive() }
        .onChange(of: router.threadID) { _, id in if let id { path.append(.thread(id)); router.threadID = nil } }
        .onChange(of: router.dmID) { _, id in if let id { path.append(.dm(id)); router.dmID = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .dcampOpenRoute)) { note in
            let route = note.userInfo?["route"] as? String
            if let id = DcampRoute.messageID(from: route) { path.append(.thread(id)) }
            else if let id = DcampRoute.dmID(from: route) { path.append(.dm(id)) }
            else if let id = DcampRoute.personID(from: route) { router.personID = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dcampPushTokenReady)) { _ in
            Task { await PushManager.shared.registerToken() }
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            ForumsHomeView(path: $path)
                .navigationDestination(for: Dest.self) { dest in
                    destination(dest).dcWideBack()
                }
                .dcampChrome(notifStore: notifStore, showNotifs: $showNotifs, showAccount: $showAccount)
        }
    }

    @ViewBuilder private func destination(_ dest: Dest) -> some View {
        switch dest {
        case .board(let id):
            if let board = session.boards.first(where: { $0.id == id }) {
                ThreadListView(board: board, path: $path)
            }
        case .thread(let id): ThreadDetailView(messageID: id).id(id)
        case .chat: ChatView()
        case .dms: DMListView(path: $path)
        case .dm(let id): DMThreadView(convoID: id).id(id)
        case .search: SearchView(path: $path)
        case .find: FindForumsView()
        }
    }

    private var personSheet: Binding<PersonRef?> {
        Binding(get: { router.personID.map(PersonRef.init) }, set: { router.personID = $0?.id })
    }

    private func openNotif(_ n: Notif) {
        toastNotif = nil
        if let id = DcampRoute.messageID(from: n.route) { path.append(.thread(id)) }
        else if let id = DcampRoute.dmID(from: n.route) { path.append(.dm(id)) }
        else if let id = DcampRoute.personID(from: n.route) { router.personID = id }
        Task { await notifStore.markSeen([n.id]) }
    }

    private func startLive() async {
        strings.lang = session.lang
        await strings.load()
        notifStore.start()

        #if DEBUG
        // Screenshot harness: skip the push prompt and jump to a screen so the
        // redesign can be captured headlessly in the Simulator.
        let env = ProcessInfo.processInfo.environment
        if let screen = env["DCAMP_SHOT_SCREEN"] {
            switch screen {
            case "board": path = [.board(1)]
            case "problems": path = [.board(4)]
            case "thread": path = [.thread(Int(env["DCAMP_SHOT_THREAD"] ?? "") ?? 11670)]
            case "shortthread": path = [.thread(230)]
            case "chat": path = [.chat]
            case "dms": path = [.dms]
            case "dm": path = [.dm(125)]
            case "search": path = [.search]
            case "settings": showAccount = true
            case "help": showHelp = true
            case "ipadsummary": summaryPin.kind = .home; summaryPin.title = "Diaspora summary"
            default: break
            }
            return
        }
        #endif

        if let route = PushManager.shared.pendingRoute {
            PushManager.shared.pendingRoute = nil
            if let id = DcampRoute.messageID(from: route) { path.append(.thread(id)) }
            else if let id = DcampRoute.dmID(from: route) { path.append(.dm(id)) }
            else if let id = DcampRoute.personID(from: route) { router.personID = id }
        }
        await PushManager.shared.enablePush()
    }
}

// MARK: - Persistent top-bar chrome (brand + search + bell + account)

private struct DcampChrome: ViewModifier {
    let notifStore: NotificationsStore
    @Binding var showNotifs: Bool
    @Binding var showAccount: Bool
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        content
            .background(Color.dcBg)
            // Custom top bar (not the system navigation toolbar): the brand must render
            // FLAT — never inside the iOS 26 glass pill that reads as a tappable button
            // (John: the top-left is not a button and must never look like one). The bell
            // and avatar ARE buttons, so they keep their own affordance.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image("DcampMark").resizable().aspectRatio(contentMode: .fit).frame(height: 22)
                Text("dcamp").font(.system(size: 18, weight: .heavy)).foregroundStyle(Color.dcInk)
            }
            Spacer()
            NotificationsBell(count: notifStore.unread) { showNotifs = true }
            Button { showAccount = true } label: { Avatar(person: session.me, size: 28) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.dcBg)
    }
}

private extension View {
    func dcampChrome(notifStore: NotificationsStore, showNotifs: Binding<Bool>, showAccount: Binding<Bool>) -> some View {
        modifier(DcampChrome(notifStore: notifStore, showNotifs: showNotifs, showAccount: showAccount))
    }
}

/// A wider back button (the iOS 26 system back was too small a tap target, esp.
/// with a mouse on Catalyst). Swipe-back still works — see the UINavigationController
/// extension below, which keeps the interactive pop gesture alive with the default
/// button hidden.
struct DCBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 54, height: 34)
                .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Replace the system back button with DCBackButton (a bigger tap target).
    func dcWideBack() -> some View {
        navigationBarBackButtonHidden(true)
            .toolbar { ToolbarItem(placement: .topBarLeading) { DCBackButton() } }
    }
}

// Keep the interactive swipe-back gesture working even though we hide the default
// back button (navigationBarBackButtonHidden otherwise disables it). The count>1
// guard stops it firing at the root. Standard, safe pattern.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - Forums home (card grid)

struct ForumsHomeView: View {
    @Binding var path: [Dest]
    @Environment(SessionStore.self) private var session
    @State private var dmUnread = 0
    @State private var chatStat: String? = nil

    // Matches the web forums grid: repeat(auto-fill, minmax(240px, 1fr)).
    private let cols = [GridItem(.adaptive(minimum: 240), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Forums")).font(.system(size: 32, weight: .heavy)).foregroundStyle(Color.dcInk)
                    Text("Forums: \(session.boards.count)").font(.system(size: 15)).foregroundStyle(Color.dcMuted)
                }

                SummarizeBar(kind: .home)

                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(session.boards) { board in
                        Button { path.append(.board(board.id)) } label: { ForumCard(board: board) }
                            .buttonStyle(.plain)
                    }
                }

                DCSectionLabel(text: "Other").padding(.top, 6)
                LazyVGrid(columns: cols, spacing: 14) {
                    Button { path.append(.chat) } label: {
                        OtherCard(icon: "bubble.left.and.bubble.right.fill", tint: Color.dcAccent,
                                  title: "Chat Room", subtitle: "Live community chat for Decent espresso owners.",
                                  stat: chatStat)
                    }.buttonStyle(.plain)
                    Button { path.append(.dms) } label: {
                        OtherCard(icon: "envelope.fill", tint: Color(red: 0.55, green: 0.36, blue: 0.86),
                                  title: "Direct Messages", subtitle: "Private conversations.", badge: dmUnread)
                    }.buttonStyle(.plain)
                    if session.showRegions || session.showRoasters {
                        Button { path.append(.find) } label: {
                            OtherCard(icon: "map.fill", tint: Color(red: 0.20, green: 0.60, blue: 0.86),
                                      title: "Find forums", subtitle: "Discover regional & roaster forums.")
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .dcColumn()
        }
        .background(Color.dcBg)
        .scrollContentBackground(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .task { dmUnread = await DcampAPI.shared.dmUnread(); await loadChatStat() }
        .refreshable { dmUnread = await DcampAPI.shared.dmUnread(); await loadChatStat() }
    }

    private func loadChatStat() async {
        let info = await DcampAPI.shared.chatInfo()
        chatStat = info.last24 > 0
            ? "Messages: \(info.total) · \(info.last24) in the last 24h"
            : "Messages: \(info.total)"
    }
}

/// Board metadata → icon + tint, mirroring the web's per-forum badges.
enum ForumStyle {
    static func icon(_ board: Board) -> String {
        switch board.slug {
        case "general-forum": return "bubble.left.and.bubble.right.fill"
        case "most-popular-topics": return "flame.fill"
        case "problems": return "wrench.and.screwdriver.fill"
        case "programmer-s-forum": return "chevron.left.forwardslash.chevron.right"
        default: return "bubble.left.fill"
        }
    }
    static func tint(_ board: Board) -> Color {
        Color(hex: board.color) ?? Color.dcAccent
    }
}

struct ForumCard: View {
    let board: Board
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: ForumStyle.icon(board))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(ForumStyle.tint(board), in: RoundedRectangle(cornerRadius: 10))
            Text(board.name).font(.system(size: 19, weight: .bold)).foregroundStyle(Color.dcInk)
            if let d = board.description, !d.isEmpty {
                Text(d).font(.system(size: 15)).foregroundStyle(Color.dcInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let n = board.messageCount {
                Text("Messages: \(n)").font(.system(size: 14)).foregroundStyle(Color.dcMuted).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .dcCard()
    }
}

struct OtherCard: View {
    let icon: String; let tint: Color; let title: String; let subtitle: String
    var badge: Int = 0
    var stat: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(Color.dcInk)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(Color.dcInkSoft)
            if let stat { Text(stat).font(.system(size: 14)).foregroundStyle(Color.dcMuted).padding(.top, 2) }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
        .dcCard()
    }
}

// MARK: - Foreground notification toast

struct NotifToast: View {
    let notif: Notif
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if notif.actor != nil { Avatar(person: notif.actor, size: 32) }
                else { Image(systemName: notif.icon).foregroundStyle(Color.dcAccent).frame(width: 32) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(notif.actor?.name ?? "dcamp").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.dcInk)
                    Text(notif.kindLabel).font(.system(size: 13)).foregroundStyle(Color.dcInkSoft).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.dcMuted)
            }
            .padding(12)
            .frame(maxWidth: 520)
            .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dcLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Account sheet

struct AccountSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Avatar(person: session.me, size: 52)
                        VStack(alignment: .leading) {
                            Text(session.me?.name ?? "—").font(.headline)
                            if session.isAdmin { Text(T("Admin")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 4)
                }
                Section {
                    Button(role: .destructive) { Task { await session.logout(); dismiss() } } label: {
                        Label(T("Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle(T("Account")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(T("Done")) { dismiss() } } }
        }
    }
}
