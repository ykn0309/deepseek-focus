# DeepSeek Focus

**English** | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Resources/AppIconRounded.png" width="104" alt="DeepSeek Focus app icon">
</p>

<p align="center">Ask DeepSeek from anywhere, Spotlight-style.</p>

DeepSeek Focus is a native macOS menu bar app. A global hotkey opens a Spotlight-style floating panel over any app, where you can ask DeepSeek questions and continue multi-turn conversations. When web search is enabled, the model can query DeepSeek's official Search API for live web pages when needed.

> **Unofficial project**: This is an independent third-party DeepSeek client, not affiliated with or endorsed by DeepSeek. The DeepSeek name, whale mark, and related trademarks belong to their respective owners; the icons in this repository are used only to identify the service this client integrates with. API usage, account balance, and search billing are the user's responsibility.

## Features

- **Global summon**: default `⌥ Space`, with a custom shortcut recorder in Settings. The panel opens on the screen containing the mouse as a floating `NSPanel`, without creating a regular document window. Left-clicking the menu bar icon opens the initial search field; right-clicking shows the menu.
- **Launch and menu bar**: enable launch at login or hide the menu bar icon in Settings. Even when hidden, the global hotkey opens the panel; use `⌘,` for Settings.
- **Spotlight-style UI**: a translucent, blurred, rounded panel. After the first message, the input moves to the bottom and the conversation expands upward.
- **Math formulas**: native SwiftMath rendering for inline `$...$` and display `$$...$$` formulas, including fractions, roots, Greek letters, subscripts, and superscripts.
- **Bilingual UI**: follows the system language by default; switch between Simplified Chinese and English in Settings, with immediate effect.
- **Streaming answers**: shows DeepSeek's reasoning, Markdown content, code blocks, tables, quotes, and clickable sources.
- **Multi-turn chat**: ask follow-ups in the same panel; history, reasoning content, and search tool results are sent with the request. Every hotkey invocation starts with a blank input. New chats use the default model, reasoning level, and web search mode from Settings; changes made inside a chat are remembered only for that chat. Clicking New Chat from the expanded view stays in the expanded view, clears the context, and focuses the bottom composer.
- **Chat history**: the initial search field has a History entry; the expanded header opens a DeepSeek-style sidebar. Search chats, start a new chat, browse Today / Last 7 days / Last 30 days / Earlier, and resume up to 50 chats. Hover over or select a row to reveal `⋯` for in-place rename or delete. Selecting another chat does not reorder the list. History is stored locally at `~/Library/Application Support/DeepSeekFocus/history.json` (mode 0600).
- **Per-chat controls**: the initial and expanded composers expose model, reasoning level, and web search controls. A change is remembered for the current chat.
- **Models from the official API**: after verifying an API key, the app fetches models, context windows, and supported reasoning levels from `https://api.deepseek.com/models`.
- **Automatic chat titles**: after the first completed answer, a short title is generated asynchronously and saved to history; a failed title request never affects the chat.
- **Configurable reasoning**: uses DeepSeek's official `Off / Low / High / Max` names (and any other levels returned by the API). Off sends `thinking: disabled` and does not send a non-official `reasoning_effort`. The setting is available in both composers and Settings.
- **Two web search modes** (Settings chooses the default for new chats; each chat can override it):
  - **Auto search**: exposes a `web_search` tool and lets the model decide when to search, using DeepSeek's official `/v1/tools/search` endpoint.
  - **Search off**: no search tool is provided and no search request is made.
- **Traceable sources**: search results appear as source cards, collapsed by default and expandable on demand. Markdown links in answers open in the browser.
- **Privacy first**: the API key is stored in a local app-data file (mode 600), not the system Keychain. There are no accounts, relays, telemetry, or analytics SDKs. Conversations go only to DeepSeek.

## Requirements

- macOS 13 Ventura or later
- A DeepSeek API key with available account balance
- Swift 5.9+ to build from source. If only Command Line Tools are installed, see the build note below.

## Usage

1. Open the app. Settings opens automatically on first launch.
2. Enter a DeepSeek API key and click **Verify & Sync**. The model list is fetched from the official API; two built-in model entries are used as a fallback.
3. Under **New Chat Defaults**, choose the default model, reasoning level, and web search mode. These affect only new chats opened from the hotkey; changes inside a chat are remembered for that chat.
4. Click **Record** to set the global shortcut. The default is `⌥ Space`.
5. Press the shortcut in any app to open a fresh initial search field. Type a question and press `Return`. The History entry in the initial field expands the panel and opens the sidebar; the button in the expanded header does the same.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open / close panel | Default `⌥ Space`; configurable in Settings |
| Send | `Return` |
| New line | `Shift + Return` |
| Close panel | `Esc` (from Settings, the first press returns to the expanded chat; the second closes the panel) |
| New chat | `⌘ N` |
| Open Settings | `⌘ ,` |

Settings is an in-panel page, reachable from the gear button, the menu bar menu, or `⌘,`. The back arrow or `Esc` returns to the expanded chat; there is no separate settings window and no Done button.

## How it works

The app calls DeepSeek's OpenAI-compatible API directly, with no backend relay:

- `GET /models`: synchronizes the model list and `effort.supported_levels`.
- `POST /chat/completions`: streams answers with `thinking`, `reasoning_effort`, conversation history, and tool definitions.
- `POST /v1/tools/search`: triggered by the model only in Auto search mode; fetches up to six results per call and respects DeepSeek's 5 QPS limit by serializing requests.

Auto search is not "search every question": the model calls the tool only when it decides live information is needed. A failed search does not fail the whole answer; the model receives the error and is asked to answer cautiously from existing knowledge.

Multi-turn requests persist and resend:

- user and assistant messages;
- reasoning content `reasoning_content` (required by DeepSeek for tool-enabled conversations);
- tool calls and tool results;
- source links already retrieved.

Each hotkey invocation resets to a blank initial field and cancels the in-flight request. Completed chats enter history automatically and can be reopened from History. Starting a new chat cancels the in-flight request and clears the context, but stays on the expanded page.

## Build from source

```bash
git clone https://github.com/ykn0309/deepseek-focus.git
cd deepseek-focus
swift package resolve
./scripts/build_app.sh
```

Artifacts:

- `dist/DeepSeek 聚焦.app`
- `dist/DeepSeekFocus-latest.zip`

The build script packages the app with a temporary ad-hoc signature and replaces `/Applications/DeepSeek 聚焦.app` with the new build. If `/Applications` is not writable, installation is skipped and the artifacts remain under `dist/`.

> **Machines with Command Line Tools only**: on macOS 26/27, the Command Line Tools SDK references the `SwiftUIMacros` compiler plugin, which is not included with CLT. The build script detects this and compiles against `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` when present. With a full Xcode installation it uses the current SDK.

The API key is stored at `~/Library/Application Support/DeepSeekFocus/credentials.json`, not in the macOS Keychain, so rebuilding or replacing the app does not trigger Keychain prompts. Paste the key in Settings on first use; old Keychain items are never read.

### Development checks

```bash
# Protocol and parsing checks
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks

# Local mock of the DeepSeek API for UI and streaming development
python3 scripts/mock_server.py 8765
```

The mock implements `/models`, streaming tool calls in `/chat/completions`, and `/v1/tools/search`. Development builds can override the endpoint and key with environment variables (these are not saved as normal settings):

```bash
DEEPSEEK_FOCUS_BASE_URL=http://127.0.0.1:8765 \
DEEPSEEK_FOCUS_API_KEY=mock-key \
"dist/DeepSeek 聚焦.app/Contents/MacOS/DeepSeekFocus"
```

## Known limitations

- This build is ad-hoc signed locally; it has no Developer ID signature and is not notarized by Apple.
- LaTeX is rendered natively by [SwiftMath](https://github.com/mgriebling/SwiftMath); building from source fetches this dependency through SwiftPM.
- Launch at login uses `SMAppService`. Keep the app in a stable location (preferably `/Applications`) or macOS may refuse to register the login item.
- After hiding the menu bar icon, the panel is reachable only through the global shortcut or by reopening the app. If the shortcut also fails to register, the app automatically restores the menu bar icon.
- If menu bar space is limited or a menu bar manager hides the icon, use the global shortcut and then `⌘,` for Settings.
- The current chat is written to history only after each answer finishes. If you switch away during streaming, the visible partial answer is saved with the chat, but the restored model context may not include the unfinished part.
- DeepSeek Search API usage is billed per successful request. See the [official documentation](https://api-docs.deepseek.com/guides/search/).
- History is stored on local disk (see Privacy); there is no cloud sync.
- The API key is stored in a local file rather than the Keychain. This is less protected than the Keychain; switch back to a Keychain implementation if you need system-level secret protection.
- Math rendering covers common LaTeX. Very complex custom macros, or formulas mixing CJK inside `\text{}`, may be limited by font fallback.

## Privacy

- The API key is stored at `~/Library/Application Support/DeepSeekFocus/credentials.json` with directory mode 0700 and file mode 0600, not in the Keychain.
- This is an intentional tradeoff: a local file is less protected than the Keychain, and other processes running as the same macOS user may be able to read it. The app never writes it to UserDefaults, logs, or chat history.
- The app contains no third-party analytics, crash reporting, or remote configuration.
- User text, chat history, and search results are sent to `api.deepseek.com`; nothing is sent anywhere else.
- Chat history is stored only at `~/Library/Application Support/DeepSeekFocus/history.json` with directory mode 0700 and file mode 0600.

## Contributing

Issues and pull requests are welcome. Before submitting, run at least:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks
```

Please do not commit real API keys, local history under `~/Library/Application Support/DeepSeekFocus`, or screenshots containing personal conversations.

## Acknowledgements

- [SwiftMath](https://github.com/mgriebling/SwiftMath): native LaTeX math rendering (MIT).
- [Pillow](https://python-pillow.org/): used by the icon generation scripts.

## License

The source code is released under the MIT License; see [LICENSE](LICENSE).

The app bundles SwiftMath (MIT); third-party notices are in `Resources/THIRD_PARTY_NOTICES.txt`. The DeepSeek name, whale mark, and related assets belong to DeepSeek. This is an unofficial tool with no affiliation or endorsement.
