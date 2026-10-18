# Repository conventions

## Release policy

- **Do not publish a release unless the user explicitly asks for one.** A normal code change, commit, or push is not a release request.
- Ordinary code changes may still be committed and pushed; only the release steps below are gated.
- Never create a new git tag, GitHub Release, DMG, or update ZIP on your own initiative.
- Do not bump `CFBundleShortVersionString` or `CFBundleVersion` for ordinary changes.
- Only when the user says “发布”, “发版”, “release”, or equivalent:
  1. bump the version and build number;
  2. run the full build and `CoreChecks`;
  3. build the app and DMG;
  4. commit, tag, and publish the GitHub Release with DMG, ZIP, and SHA-256 assets.
- The local `/Applications/DeepSeek Focus.app` must not be replaced during normal development or update testing unless the user explicitly asks to install.

## Local test installs

- When app code changes and the user wants to test locally, run `./scripts/install_local.sh`.
- This stages a fresh build, quits the running app, replaces the installed app, and relaunches it.
- Local test installs are **not releases**: do not bump the marketing version, create a tag, or publish a GitHub Release for them.
- The installed test build can carry the same version number as the latest release; only bump the version during an explicitly requested release.

## Build and test

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks
```

Build without installing locally:

```bash
INSTALL_DIR=/tmp/deepseek-focus-no-local-install ./scripts/build_app.sh
./scripts/build_dmg.sh
```

## Safety

- Never delete or overwrite user data under `~/Library/Application Support/DeepSeekFocus/`.
- Never print or commit API keys or credentials.
- Keep changes scoped and verify builds before reporting completion.
