# dcamp — iOS & Mac Catalyst app

A native iOS / iPadOS / **Mac Catalyst** wrapper around the
[dcamp](https://decentespresso.com/support/dcamp/) single-page app (the Decent
Diaspora forum). It hosts the existing dcamp SPA in a `WKWebView` and adds the
native capabilities Apple expects from an App Store app, so the web frontend
stays the single source of truth while the app feels native.

## What's native (and why it's not "just a website")

App Store guideline **4.2** rejects apps that are only a website in a shell. This
wrapper adds real native value:

- **Push notifications** — APNs registration + device-token forwarding, tap-to-route
  deep links into the SPA (`#/message/123`, `#/pings/…`, etc.).
- **Photo / camera attachments** — `WKWebView` file inputs use the native picker
  and camera (Info.plist usage strings included).
- **Native share sheet** — the SPA can call `dcampNative.share(url, title)`.
- **Pull-to-refresh** on the web content.
- **Offline detection** — a native "You're offline / Try again" screen via `NWPathMonitor`.
- **External links** open in `SFSafariViewController`; dcamp links stay in-app.
- **Keychain login** — remembers the `/support` login and offers best-effort autofill.
- **Haptics** and **app icon badge** controllable from the SPA.
- **Edge-swipe back/forward** navigation.

## Project layout

```
project.yml                 XcodeGen spec (regenerate the .xcodeproj from this)
Sources/
  DcampApp.swift            SwiftUI @main + AppDelegate adaptor
  AppDelegate.swift         APNs registration + notification taps
  RootView.swift            SwiftUI → UIKit bridge
  WebViewController.swift    Core: WKWebView, refresh, offline, JS bridge, links
  OfflineView.swift         Native offline panel
  PushManager.swift         Push permission, token forwarding, payload routing
  Reachability.swift        NWPathMonitor wrapper
  KeychainStore.swift       /support credential storage
  AppConfig.swift           Base URL, allowed hosts, bridge names
Resources/
  Info.plist                Usage strings, background modes, orientations
  Dcamp.entitlements        aps-environment
  Assets.xcassets           AppIcon (placeholder), AccentColor, LaunchBackground
```

## Build & run

Requires Xcode 26+, [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate                       # (re)create Dcamp.xcodeproj from project.yml
open Dcamp.xcodeproj                     # then run, or:

# iOS simulator
xcodebuild -scheme Dcamp -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build

# Mac Catalyst
xcodebuild -scheme Dcamp \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

Set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode → Signing) before building
for a device or App Store submission.

## JS bridge for the dcamp SPA

When running inside the app, `window.dcampNative` is available and
`document.documentElement` gets the classes `dcamp-native dcamp-ios`. The SPA can
feature-detect and progressively enhance:

```js
if (window.dcampNative) {
  dcampNative.requestPush();                  // prompt for notifications
  dcampNative.share(location.href, title);    // native share sheet
  dcampNative.setBadge(unreadCount);          // app icon badge
  dcampNative.haptic('success');              // light|medium|heavy|success|warning|error
  dcampNative.saveLogin(email, password);     // remember in Keychain
  dcampNative.clearLogin();
  const creds = await dcampNative.getLogin();  // {email, password} | null
}
```

## Backend (push) — implemented in dcamp

The dcamp backend half is built (in `/d/lib/dcamp_push.tcl` + `schema.sql` +
`dcamp_app.tcl`). The app registers its APNs token by calling, **through the web
view** (so the `/support` cookie authenticates it):

```
POST /support/dcamp/api.adp?action=push_register
     platform=apns&token=<hex>
```

which upserts into `dcamp_push_tokens (person_id, platform, token, …)`, keyed on
the person resolved from the cookie. Registration fires on every page load and
when the token arrives; it's idempotent, and no-ops cleanly until the user is
logged in.

Outbound delivery is a transport-neutral seam: the dcamp notification event model
(built separately) calls `dcamp_notify <person_id> <title> <body> <route>`, which
fans out to APNs (this app), Web Push (browsers), and the in-app inbox. APNs uses
token-based JWT (ES256, signed via `openssl`) over HTTP/2 (`curl --http2`), with a
`route` key in the payload that this app turns into a deep link.

**Still required before push actually fires:** Apple credentials, set on the
server via Adminland → Settings (`apns_team_id`, `apns_key_id`, `apns_topic` =
`com.decentespresso.dcamp`), plus the `.p8` auth key dropped at
`/d/admin/apns/AuthKey.p8`. Until those exist, sends are a silent no-op. There's
an admin smoke-test action `push_test` once configured.
