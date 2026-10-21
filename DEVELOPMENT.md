# Development

This file keeps the implementation and packaging details out of the user-facing README.

## Project layout

- `Sources/DeepSeekFocusCore`: API client, SSE decoding, chat protocol, models, and version comparison.
- `Sources/DeepSeekFocus`: SwiftUI/AppKit app, panel, menu bar item, settings, history, and update checker.
- `Sources/CoreChecks`: lightweight executable checks (no XCTest).
- `Resources`: Info.plist, icons, localizations, and third-party notices.
- `scripts`: build, packaging, icon generation, localization generation, and a local mock API.

## Build

Requirements: macOS 13+, Swift 5.9+.

```bash
git clone https://github.com/ykn0309/deepseek-focus.git
cd deepseek-focus
swift package resolve
./scripts/build_app.sh
```

`build_app.sh` only writes `dist/`; it does not replace the installed app. Use `./scripts/install_local.sh` for an explicit local install. Local installs set `STABLE_ADHOC_SIGNING=1`, which embeds a stable designated requirement so Accessibility permission survives rebuilds. Public builds must use `SIGN_IDENTITY` with a Developer ID certificate.

`build_app.sh` creates:

- `dist/DeepSeek Focus.app`
- `dist/DeepSeekFocus-latest.zip`

It uses a temporary ad-hoc signature. To install it locally, run:

```bash
./scripts/install_local.sh
```

### Command Line Tools only

On macOS 26/27, the Command Line Tools SDK references the `SwiftUIMacros` compiler plugin, which is not shipped with CLT. The build script detects this and uses `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` when available. A full Xcode installation uses the current SDK.

## API behavior

The app calls the OpenAI-compatible DeepSeek API directly:

- `GET /models`: model list and `effort.supported_levels`.
- `POST /chat/completions`: streaming chat with `thinking`, `reasoning_effort`, history, and tool definitions.
- `POST /v1/tools/search`: called by the model only in Auto search mode; at most six results per call, serialized to respect the 5 QPS limit.

Auto search is model-driven, not a search on every question. A failed search is returned to the model as an error and does not fail the whole answer.

Multi-turn requests resend user/assistant messages, `reasoning_content`, tool calls/results, and retrieved source links. Each hotkey invocation starts a new blank field and cancels the in-flight request. New chats clear context but stay on the expanded page.

## Local data

- API key: macOS Keychain (`com.kainan.deepseekfocus` / `deepseek-api-key`). Existing `credentials.json` files continue to work and are migrated after the key is next saved. If Keychain access is unavailable, the app falls back to the legacy 0600 file.
- History: `~/Library/Application Support/DeepSeekFocus/history.json` (0600, directory 0700), with `history.backup.json` and preserved `history.corrupt-*.json` files.
- No accounts, telemetry, crash reporting, or remote configuration.

## Checks

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks
swift build
```

The first command covers protocol/parsing behavior and version comparison. The UI is built with SwiftUI; there is no XCTest target.

## Local mock API

```bash
python3 scripts/mock_server.py 8765
```

The mock implements `/models`, streaming tool calls in `/chat/completions`, and `/v1/tools/search`. Override the endpoint and key only for development:

```bash
DEEPSEEK_FOCUS_BASE_URL=http://127.0.0.1:8765 \
DEEPSEEK_FOCUS_API_KEY=mock-key \
"dist/DeepSeek Focus.app/Contents/MacOS/DeepSeekFocus"
```

These environment variables are not saved as normal settings. Remove them from the shell after testing.

## Packaging

```bash
./scripts/build_app.sh
./scripts/build_dmg.sh
```

The DMG contains `DeepSeek Focus.app` and an Applications shortcut. Both the app and DMG remain ad-hoc signed and unnotarized.

For a release, publish the DMG, the ZIP, and a SHA-256 checksum file. The app checks `https://api.github.com/repos/ykn0309/deepseek-focus/releases/latest`; only the latest published, non-prerelease release is considered.

### Developer ID and notarization

The default build is ad-hoc signed. To produce a distributable build, provide a Developer ID Application identity and a `notarytool` keychain profile:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
./scripts/build_dmg.sh
NOTARY_PROFILE="deepseek-focus-notary" ./scripts/notarize_dmg.sh
```

`build_app.sh` uses hardened runtime and a secure timestamp when `SIGN_IDENTITY` is not `-`. Notarization requires an Apple Developer account; without a Developer ID certificate the app must remain ad-hoc signed.

## In-app updates

The updater requires both the ZIP and `.sha256` release assets. It:

1. downloads the ZIP from the GitHub release into a temporary file;
2. downloads the checksum file and verifies SHA-256;
3. extracts with `ditto`, checks `CFBundleIdentifier` and the version against the release tag, and runs `codesign --verify --deep --strict`;
4. stages the app under `~/Library/Application Support/DeepSeekFocus/Updates/`;
5. launches a detached helper script, then terminates the app.

The helper waits for the app PID to exit, moves the current app to a timestamped backup, copies the staged app into place, strips quarantine, removes the backup, and opens the new app. If copying fails, it restores the backup and reopens it. The helper log is `~/Library/Application Support/DeepSeekFocus/Updates/install.log`.

Automatic installation is only attempted when the running app is under `/Applications` and that directory is writable. Otherwise the updater shows an error and the user can open the Release page.

The checksum and code-signature checks protect against corrupt or partially downloaded packages and obvious bundle mismatches. The app is ad-hoc signed, so this is not a cryptographic publisher identity check; a compromised GitHub account or repository could still publish a malicious release. Keep that in mind when enabling automatic installs.

## Known limitations

- Ad-hoc signature; no Developer ID and no Apple notarization.
- SwiftMath is fetched through SwiftPM on the first source build.
- Launch at login uses `SMAppService`; the app should stay in a stable location, preferably `/Applications`.
- Hiding the menu bar icon leaves the global shortcut as the main entry point. If shortcut registration also fails, the app restores the icon automatically.
- The current chat is written after each answer finishes. Switching away mid-stream saves the visible partial answer, but restored model context may omit the unfinished part.
- Search API usage is billed per successful request.
- History is local only; there is no cloud sync.
- The API key prefers Keychain storage; the legacy local file is retained only as a fallback when Keychain access is unavailable.
- Common LaTeX renders natively; complex custom macros or CJK inside `\text{}` may be limited by font fallback.
- Automatic installation requires a writable `/Applications` and the ZIP + SHA-256 assets on the latest release.

## Contributing

Issues and pull requests are welcome. Run the checks above before submitting. Do not commit API keys, local history under `~/Library/Application Support/DeepSeekFocus`, or screenshots containing personal conversations.
