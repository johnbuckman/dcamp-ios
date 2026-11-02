# Mac updates

Mac Catalyst uses [Sparkle 2](https://sparkle-project.org/documentation/programmatic-setup/)
through an AppKit bundle. iPhone/iPad builds do not embed the bundle or Sparkle.
Automatic checks default to on: once at process startup, then every 24 hours while
dcamp is running. Sparkle persists the member's choice in Settings → App updates.
Disabling automatic checks disables the startup check too. **Check for Updates…**
in the dcamp menu and Settings still works manually. Installing an update requires
the member's approval; downloads are not silently installed.

The app follows the latest **stable** GitHub release. Both the feed and archive
must be Ed25519 signed. Archives are verified before extraction. Sparkle also
validates the app's code signature. HTML release notes are disabled because
Catalyst cannot use Sparkle's macOS WebKit release-note view.

## One-time setup on the release owner's Mac

Older dcamp versions have no updater. Members must manually install the first
release containing this feature. Before publishing it, the release owner must
generate and retain the signing key; a checkout deliberately contains no key.

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -scheme Dcamp -derivedDataPath build/mac
SPARKLE_BIN="$PWD/build/mac/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account com.decentespresso.dcamp
mkdir -p secrets
"$SPARKLE_BIN/generate_keys" --account com.decentespresso.dcamp -p > secrets/sparkle-public-key.txt
```

The private key remains in the login Keychain. Back it up securely according to
[Sparkle's key guidance](https://sparkle-project.org/documentation/); losing it
breaks the update chain. Never commit or publish it. `-p` prints only the public
key. Put that public value into the ignored `secrets/Sparkle.xcconfig`:

```xcconfig
DCAMP_SPARKLE_PUBLIC_KEY = PASTE_THE_PUBLIC_KEY_HERE
```

Pass `-xcconfig secrets/Sparkle.xcconfig` to **every Mac release build**. A Catalyst
Release build fails without a valid public key. A keyless Debug build runs with
updates unavailable. iOS builds do not require a Sparkle key.

## Every Mac release

1. Increment **both** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   `project.yml`. Sparkle compares `CFBundleVersion` (the build number).
2. Build the Mac app from the intended clean commit using the existing Developer
   ID, hardened-runtime and timestamp options in `CLAUDE.md`, **plus**
   `-xcconfig /absolute/path/to/secrets/Sparkle.xcconfig`. Xcode embeds and signs the
   updater bundle and Sparkle; keep the nested frameworks and helper services.
3. Notarize the app's zip, staple the app, and verify Gatekeeper acceptance using
   the existing release recipe. Then generate the final archive and feed:

   ```sh
   python3 tools/prepare_mac_update.py \
     --app build/mac/Build/Products/Release-maccatalyst/dcamp.app \
     --tag v1.26 \
     --sparkle-bin build/mac/SourcePackages/artifacts/sparkle/Sparkle/bin \
     --output build/mac-release-v1.26
   ```

   The helper checks the public key against the release owner's Keychain account,
   code signature, notarization, staple, feed, archive signature and build number.
   It does not publish anything. The output directory must be empty.
4. Upload **both** `dcamp-macos-latest.zip` and `appcast.xml` in the same stable
   GitHub release. Prefer creating it as a draft, uploading all assets, then
   publishing it as latest; do not mark it prerelease. Include the existing IPA
   and installer assets as usual. Preserve the exact Mac zip filename.
5. Check that these URLs download the two assets:
   - `https://github.com/johnbuckman/dcamp-ios/releases/latest/download/appcast.xml`
   - `https://github.com/johnbuckman/dcamp-ios/releases/latest/download/dcamp-macos-latest.zip`
6. Test an installed older updater-enabled version with **Check for Updates…**.
   The feed points to an immutable, versioned `/releases/download/vX.Y/…` archive,
   so publishing another latest release cannot change the file mid-download.

The generated feed contains one full update and no deltas. **Do not edit the XML
or zip after signing.** Keep uploading a signed feed for subsequent releases;
publishing a latest release without it breaks checks for existing installations.

## Validation

```sh
xcodegen generate
xcodebuild -scheme MacUpdaterTests \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath build/updater CODE_SIGNING_ALLOWED=NO test
python3 -m unittest discover -s UpdaterToolTests -v
```

The host tests load the actual embedded AppKit/Sparkle bridge in Catalyst, and
exercise configuration, state propagation, opt-out and failures without network
requests. Test unsigned/ad-hoc builds locally; public distribution must use the
Developer ID/notarization steps above.
