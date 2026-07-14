# dcamp — Native SwiftUI App Plan

Status: **active build** (M1–M3 in progress). Last updated 2026-07-14.

This replaces the WKWebView-wrapper approach (see git history) with a **fully native
SwiftUI** client for dcamp. The wrapper's push/keychain/reachability plumbing and the
whole server-side APNs stack are reused; the web-view UI is retired.

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
- **M1** — skeleton + API actor + auth + boards + split-view shell. *(in progress)*
- **M2** — read threads + native Trix HTML rendering.
- **M3** — post & interact + embedded-Trix composer + uploads + mentions.
- M4 — native notifications (push_register via API, notif_poll, deep-link).
- M5 — DMs + chat.
- M6 — search, people, server-driven i18n.
- M7 — polish, app icon, signing, TestFlight, App Store.

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
