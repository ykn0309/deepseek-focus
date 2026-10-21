# Repository conventions

## Release policy

- **Do not publish a release unless the user explicitly asks for one.** A normal code change, commit, or push is not a release request.
- Ordinary code changes may still be committed and pushed; only the release steps below are gated.
- Never create a new git tag, GitHub Release, DMG, or update ZIP on your own initiative.
- Do not bump `CFBundleShortVersionString` or `CFBundleVersion` for ordinary changes.
- Only when the user says “发布”, “发版”, “release”, or equivalent:
  1. bump the marketing version and `CFBundleVersion`;
  2. run the full build and `CoreChecks`;
  3. build the app and DMG;
  4. commit, tag, and publish the GitHub Release with DMG, ZIP, and SHA-256 assets.
- The local `/Applications/DeepSeek Focus.app` must not be replaced during normal development or update testing unless the user explicitly asks to install.

## Versioning

- From v1.9 onward, public releases use two-component marketing versions: `1.9`, `1.10`, `1.11`.
- Increase `CFBundleVersion` for builds; the build number is internal and only shown in About.
- The Settings update section shows only the marketing version, without the build number.
- Do not rewrite already-published tags, releases, asset filenames, checksums, or bundles. Historical v1.8.x releases keep their original numbers.
- Only use a third component (for example `1.9.1`) for a critical hotfix when a new minor release is not appropriate.

## Local test installs

- When app code changes and the user wants to test locally, run `./scripts/install_local.sh`.
- This stages a fresh build, quits the running app, replaces the installed app, and relaunches it.
- Local test installs are **not releases**: do not bump the marketing version, create a tag, or publish a GitHub Release for them.
- `install_local.sh` uses `STABLE_ADHOC_SIGNING=1` so local Accessibility grants can survive rebuilds. Do not use that signing mode for a public release; public builds need a Developer ID identity.
- The installed test build can carry the same version number as the latest release; only bump the version during an explicitly requested release.

## Build and test

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run CoreChecks
```

Build without installing locally:

```bash
./scripts/build_app.sh
./scripts/build_dmg.sh
```

`build_app.sh` only writes `dist/`. Use `./scripts/install_local.sh` when you explicitly want to replace `/Applications/DeepSeek Focus.app`.

## Safety

- Never delete or overwrite user data under `~/Library/Application Support/DeepSeekFocus/`.
- Never print or commit API keys or credentials.
- Keep changes scoped and verify builds before reporting completion.
