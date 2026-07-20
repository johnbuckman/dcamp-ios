# dcamp — Native SwiftUI App Plan

Status: **active build** (M1–M3 in progress). Last updated 2026-07-14.

This replaces the WKWebView-wrapper approach (see git history) with a **fully native
SwiftUI** client for dcamp. The wrapper's push/keychain/reachability plumbing and the
whole server-side APNs stack are reused; the web-view UI is retired.

## 2026-07-14 — Remaining feature list (near-complete)
- **@mention autocomplete**: editor.html detects `@query`, bridges to Swift, a native
  overlay lists `mention_search` results, tap inserts a `#/p/id` link. In every composer.
- **Category picker** on new threads (session.categories for the board) → message_create.
- **Chat edit/delete** (admin) via per-line ⋯ menu (chat_update via editChat mode / chat_delete).
- **DM unread badge** on the Direct Messages home card (dm_unread).
- **DM invite/remove participants** (dm_invite/dm_remove) via a reusable `PeopleSearchSheet`.
- **Search filters**: type pills (threads/comments/chat/DMs) + year menu → search(types,years).
- **Translation**: content ships pre-translated in `body_tr`; `TranslatableText` shows the
  translation with a per-block "Show original" toggle (messages/comments/chat/DMs).
- **Streaming bot replies + live comments**: thread polls every 3s (MainActor `.task` loop),
  reconciling only on change — @derek/@deepseek replies stream in, new comments appear live.
- **DEFERRED — Adminland**: blocked, not just UI. `is_admin` = `decent_admin_verified`
  (emailed adminpw cookie), which native bearer requests can't hold → `is_admin` is always
  false natively. Needs a server decision on granting admin over the bearer token.
- **Quote & reply**: message/comment ⋯ → inserts a blockquote of the content into the
  thread's reply composer (own model, `dcampInsertQuote`) and scrolls to it.
- **iPad two-pane DMs**: on regular width, DMs render as list + thread side by side
  (verified on iPad); compact stays push navigation.
- **Regional/roaster forum discovery**: `FindForumsView` (projects_discover + project_join/
  leave), reached from a gated "Find forums" home card. Hidden while show_regions/roasters
  are off (as they are for this community now).

Only **Adminland** remains, deferred pending the server admin-auth decision above.

## 2026-07-14 — Web-parity fixes (composer, summaries, iPad sidebar)
- **Thread composer**: replaced the (easy-to-miss / canPost-gated) "Reply" button with
  an **always-visible inline rich-text composer at the bottom of the thread** (like the
  web). Non-owners now see a clear read-only notice instead of nothing.
- **Summaries work like the web**: Summarize now **expands the summary inline** below the
  bar (Show/Hide, regenerates on window change) instead of a modal sheet.
- **iPad side panel**: "Show in sidebar" (regular width) pins the summary to a
  **persistent left panel** (`SummaryPin` + `SummarySidebarView`), alongside content —
  verified on an iPad simulator.
- Note: if an owner still sees the read-only notice, their app-login email may not match
  their `dcamp_members` owner record (identity split) — a per-account diagnosis.

## 2026-07-14 — Feature audit + big feature pass
Full audit of the web forums/DM/chat/settings/summaries surface (see the agent
inventory). Fixed two broken flows and implemented a large batch of missing features.

**Fixed:** posting a comment/message (composer now reads the editor HTML on-demand,
so Post/Send no longer depend on Trix change-events reaching Swift — the button was
permanently disabled); creating a DM after a name search (push now happens after the
sheet dismisses, and errors surface).

**Implemented:**
- **Settings** (`SettingsView`, from the account button): display name + about, city/
  country + show-location, notification prefs matrix (mention/dm/comment_own/
  comment_followed × Popup/Email), summaries-by-email frequency, muted-people list,
  Basecamp link status, close account, sign out. (settings_save, location_save,
  notif_prefs_get/save, summary_prefs_get/save, person_mutes/unmute, account_close)
- **Summaries**: ✨ Summarize bar on home / forum / thread / chat with a window
  picker; on-demand AI summary rendered in a sheet. (home/forum/thread/chat_summary)
- **Reactions (boosts)**: emoji reaction pills with counts on messages/comments/chat,
  "😊+" picker, toggle. (boost_toggle)
- **Overflow ⋯ menu**: copy link, edit (message_update/comment_update via composer
  preload), delete (message_status/comment_delete), admin pin (message_pin), Problems
  status (message_set_status).
- **Person card actions**: Message (dm_direct), Mute/Unmute, Report (report_person).
- **DM archive** (dm_archive, context menu).
Verified in the Simulator: thread (summarize bar + ⋯ + reactions), settings loaded
with real data, chat reactions.

### Still missing (next batch — `implement all` continues)
@mention autocomplete in the composer (needs editor.html JS bridge); category picker
on new-thread + Problems status filter on the board list; DM invite/remove participants
UI + unread badge; chat edit/delete (admin); quote-&-reply; search type/year/sort
filters; bot streaming replies; progressive per-block translation; adaptive polling;
DM two-pane on iPad; regional/roaster forum discovery; Adminland.

## 2026-07-14 — DM + chat brought in line with the web (follow-up)
Compared the native chat/DM against the actual web screens and corrected them:
- **DMs are chat bubbles** (own = blue/right + avatar + timestamp, others = grey/left)
  — I'd wrongly made them a flat list. **Chat stays the author-headed flat list.**
- **Both chat & DM composers are now the embedded Trix rich-text editor** (toolbar +
  @mention), via a reusable `InlineComposer` — not the old plain text field.
- Fixed a placeholder **mojibake** (added `<meta charset="utf-8">` to editor.html).
Verified in the Simulator: DM bubbles + rich composer, chat flat + rich composer.

## 2026-07-14 — UI redesigned to match the dcamp web app
Replaced the iOS-idiomatic split-view/bubble UI with one that **closely follows the
dcamp web SPA** (studied live via the browser + dcamp.css). Warm-paper theme
(`Sources/Views/DcampTheme.swift`: bg #fdf9f3, green #16a34a accent, 14px cards,
soft shadows), forced light appearance. Single centered column via `NavigationStack`
(not master/detail). Forums **card grid** home with a top bar (brand + bell + avatar).
Rich thread rows (subject + category pill + preview + machine badge + comment count),
filter pills, "+ New message". Centered message card + author-headed comments. **Chat
& DMs are author-headed lists (not bubbles)** with DECENT + machine badges, green
@mentions, blue links. Login mirrors the web card. Verified screen-by-screen in the
iOS Simulator against the web. *Deferred (visual extras):* the ✨ Summarize bar,
per-post reaction display, and thread-row thumbnails.

## Locked decisions
- **Fully native SwiftUI** UI (not a web-view wrapper).
- **iOS 17 minimum** (enables `@Observable`, `NavigationSplitView`, modern concurrency).
- **Rich-text editor = embedded Trix in a WKWebView** (editor only) so composed HTML stays
  byte-compatible with the web app. Rendering of existing bodies is native.
- **Real-time = polling for v1**, behind a `RealtimeService` protocol seam so SSE can drop
  in later with no UI change. APNs (already built) covers background. No WebSocket.
- Keep dcamp's existing **`api.adp?action=…` endpoint architecture** — no REST/GraphQL
  rewrite. All server changes are **additive and versioned** (`client=native` + bearer
  token); the live SPA behaves byte-identically without the flag/header.

## What the app talks to
Single JSON endpoint `POST/GET /support/dcamp/api.adp?action=<name>`, ~150 actions.
Native client uses ~30: auth_email/auth_login/auth_create/auth_logout, bootstrap,
projects, messages, message, comment_one, message_create/update/pin/status,
comment_create/update/delete, boost_toggle, subject_check, chat*, dm_*, notif_poll/
notif_seen/notif_prefs_*, activity_summary/home_summary, person/person_card/mention_search,
search, translate/ui_strings/ui_map, upload/url_title, push_register/unregister/test.

Envelope: `{"ok":true, …}` / `{"ok":false,"error":"…"}`.
Per-request identity today = `$::dcamp_uid = [email_pw_to_artistid "" ""]` from the
`/support` login cookie; the API gate rejects when it's empty.

## Server changes (all in /d, additive, reviewed before CVS commit)
MUST (blocks native):
1. **Token auth** — `lib/dcamp_native.tcl` (isolated, mirrors dcamp_push.tcl pattern):
   `dcamp_api_tokens` table; `auth_token` action (verify email+pw via
   `email_pw_to_artistid`, mint opaque token, store with device_id); a **Bearer lane** in
   `dcamp_api_dispatch` that populates the same `$::dcamp_uid` before the login gate;
   `auth_logout`/`token_revoke` clears it. Everything downstream unchanged.
2. **`push_register` over bearer** — free once (1) lands; drop the cookie requirement.
3. **Embedded-Trix editor page + token'd `upload`** — small `native_editor.adp` hosting
   Trix + upload glue; `upload` accepts the bearer token.
SHOULD:
4. **`client=native` structured content** on body actions: add `body_html`,
   `mentions[]`, `attachments[]` (type/url/w/h), `youtube[]` alongside HTML.
5. **JSON envelope/type normalization** per-action as milestones land (numbers-as-numbers,
   ISO-8601, explicit nulls) — only when `client=native`.
LATER: ui_strings ETag/version; consolidated `sync` poll; SSE realtime (plugs into the
existing `dcamp_notify` fan-out as `dcamp_push_sse`).
NOT changing: endpoint architecture, business logic, DB schema (except tokens table),
CORS (native isn't a browser), the SPA.

## iOS architecture
- SwiftUI + `@Observable` MVVM.
- `DcampAPI` actor — one typed async client; `call<T:Decodable>(action, params)`; injects
  `Authorization: Bearer`.
- `Codable` models pinned to real JSON (contract pass).
- `SessionStore` — email→auth_login→token, token in Keychain (reuse KeychainStore).
- `RealtimeService` protocol → `PollingRealtime` now (notif_poll/message_poll/dm_poll).
- Responsive: `NavigationSplitView` 3-column on iPad/Mac, `TabView`+`NavigationStack` on
  compact iPhone, switched on `horizontalSizeClass`.

## Reuse from existing repo
Keep: PushManager, AppDelegate, KeychainStore, Reachability, git repo, XcodeGen, bundle id,
the whole server APNs stack (dcamp_push.tcl, AuthKey, dcamp_push_tokens, push_register).
Retire: WebViewController + web bridge, OfflineView's web coupling.

## Milestones
- **M1 ✅ DONE** — skeleton + API actor + token auth + boards + split-view shell.
  Verified from the Catalyst binary: login→bootstrap→4 boards decoded, phase=loggedIn.
- **M2 ✅ DONE** — read threads + native Trix renderer (paragraphs, headings, lists,
  quotes, links, @mentions, images, YouTube). Verified: real thread 11670 parsed to
  correct block structure; cross-post links navigate in place.
- **M3 ✅ DONE (core)** — embedded-Trix composer (bundled trix.js/css + editor.html),
  new-thread + reply, image upload (PhotosPicker → `upload`), boost method. Verified:
  client posted a comment from the binary → persisted in DB. *Deferred:* in-editor
  @mention autocomplete (mention_search) — follow-up.
- **M4 ✅ DONE (core)** — `push_register` over the bearer token, foreground
  `notif_poll` on the RealtimeService seam, notification inbox + bell badge +
  app-icon badge, `notif_seen`, and push-tap deep-linking into the target thread.
  Verified from the binary: app registered a push token + polled a seeded mention
  and resolved its route → message id. *Not testable here* (needs a real signed
  device): live APNs delivery + the banner UI. *Also deferred:* the notif-prefs
  settings screen (API methods exist).
- **M5 ✅ DONE** — native **chat** room (poll + post) and **DMs** (conversation list,
  bubble thread with polling, new DM via people search → dm_create/dm_send). Sidebar
  gained Chat / Messages / Search sections beside Forums. Verified from the binary as a
  real member (Ricky, user #5): chat 80 lines, DM thread decoded, DM created + sent.
- **M6 ✅ DONE** — **search** (threads/comments/chat + people, tap-to-open via Router),
  **person profiles** (person_card sheet, opened by tapping @mentions/avatars), and the
  **i18n** mechanism (ui_map load + `t()` with English fallback; app language from
  bootstrap). Verified: search 97 results/53 people, person card loads, mention→person
  routing wired. Note: only nav labels are localized so far — broader `t()` coverage is
  incremental. *Deferred:* DM/chat rich composer (uses a plain text SendBar today, not
  Trix); search filters (types/years); notif-prefs screen.
- M7 — polish, **app icon ✅** (coffee cup on a warm espresso gradient; single-size
  1024 universal icon, source SVG in scratchpad `dcamp_icon.svg`), signing, TestFlight,
  App Store.

### Routing (added in M6)
A shared `Router` (`@Observable`, injected app-wide) turns tapped links inside rendered
content into navigation: `#/p/<id>` → PersonCard sheet, `#/message/<id>` → thread (in
place inside a thread, or a sheet from search/chat/DMs). `TrixContentView` reads it, so
mentions and cross-post links work everywhere the renderer is used.

## Build & verification status (2026-07-14)
- Builds clean for **Mac Catalyst** (ad-hoc, throwaway push-free entitlements
  `/tmp/dcamp-local.entitlements`; `-derivedDataPath build`).
- Verified **headlessly** via a DEBUG env-gated smoke hook in `SessionStore.start()`
  (`DCAMP_SMOKE_EMAIL/PW`, `_MSG`, `_POST`) — because the GUI-control approval prompt
  can't be accepted while John is away. Pixel-level SwiftUI rendering + the Trix editor
  UI + PhotosPicker upload round-trip are **not yet visually confirmed** — do a visual
  pass (approve computer-use control, or just run `/Applications`-installed build).

## Server changes made — UNCOMMITTED in /d (for John's review)
- **`lib/dcamp_native.tcl`** (new): `dcamp_api_tokens` table (lazy create),
  `auth_token` (mint), Bearer lane `dcamp_native_apply_bearer` (sets `$::dcamp_uid`
  AND synthesizes `email`/`cryptpw` onto the request headers so cookie-based identity
  — `dcamp_is_owner`, posting gates — works for cookie-less native requests),
  `token_revoke`.
- **`lib/dcamp_app.tcl`**: 4 tiny hooks — `auth_token` in the pre-gate whitelist +
  `dcamp_auth_run`; `catch { dcamp_native_apply_bearer }` after `$::dcamp_uid` is set;
  `token_revoke` action; `source .../dcamp_native.tcl` at EOF.
- Reload locally with `/admin/lib_reload.adp` (cvs-free hot reload). Also add the
  `dcamp_api_tokens` DDL to `schema.sql` before prod (not yet done).
- **`lib/dcamp_push.tcl` — real pre-existing bug fixed:** `dcamp_push_register`'s
  token regex `{32,512}` exceeds Tcl's 255 max repetition count, so it threw
  "invalid repetition count(s)" and **every** APNs registration failed (affects the
  web/PWA push path too, not just native). Changed to `{32,}`. Verified: registration
  now returns ok and stores the row. ⚠️ This touches the committed push file — review.

## Local test fixtures (disposable dev DB only — not prod)
Made a synthetic `…@example.com` account a posting-capable beta user for testing:
a `dcamp_members` row + a qualifying `carts`/`cart_detail` DE1 order (survives the
owner reconcile) + a fake `dcamp_bc_user_tokens` row (satisfies the beta BC-link gate).
Test content created: thread 11692, comments on 11670/11692.

## Biggest risks
1. Rich text (render + compose) — embedded-Trix mitigates compose; structured content
   mitigates render.
2. Feature-parity treadmill vs. the actively-evolving SPA.
3. Server-side i18n consumption.
4. No device push until App ID + Push capability + Decent-team dev cert are set up.

## Open / needs John
- A dcamp test login for verifying against **live** prod (local uses a throwaway account).
- Register App ID `com.decentespresso.dcamp` + Push capability in the portal; device dev
  cert for team XLS3XF57J8.
- Review the /d Tcl additions before CVS commit.
