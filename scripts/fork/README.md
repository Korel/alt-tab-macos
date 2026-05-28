# Fork CI / customizations

This is a fork of [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos).
Everything in this directory is **fork-only** and does not exist upstream, so it
never conflicts with the daily upstream sync. This doc explains the deliberate
choices the fork makes, so they aren't accidentally "fixed" or reverted later.

## Goals

1. Stay current with upstream automatically.
2. Produce an installable `.dmg` (upstream only ships signed/notarized builds
   through its own infrastructure).
3. Unlock **Pro** in the self-built app. AltTab is **GPLv3** (see `LICENCE.md`),
   which grants the right to build and run your own copy; the author also states
   people may self-build to use Pro features without a license.

## How it fits together

### `.github/workflows/sync-upstream.yml` (Linux, daily + manual)
- Merges `lwouis/alt-tab-macos` `master` into this fork's `master` every day so
  the fork stays current. It MERGES (not fast-forwards) because `master` carries
  fork-only files (these workflows, `scripts/fork/`). A merge conflict fails the
  job for manual resolution rather than force-pushing.
- Triggers the DMG build **only when upstream publishes a new release tag**
  (`v*`), not on every commit — this keeps the expensive macOS build (billed at
  10x) to roughly once per upstream release.

### `.github/workflows/build-dmg.yml` (macOS, on new release tag + manual)
Builds an **unsigned** DMG and publishes it as a GitHub Release tagged
`fork-v<version>`. Key steps and *why*:
- **Version** comes from the latest upstream `v*` tag (no `semantic-release`).
- **Unsigned build:** the Release scheme hardcodes upstream's Developer ID cert,
  which the fork can't use. Signing is forced off via `config/local.xcconfig`
  overrides + `xcodebuild` flags.
- **Pro unlock:** `scripts/fork/apply_pro_unlock.sh` runs right before the build
  (see below). Applied at build time, **never committed to source**, so `master`
  stays a clean mirror of upstream and the sync never conflicts.
- **Ad-hoc re-sign with a stable identifier:** an unsigned build's default
  ad-hoc signature changes every build, so macOS keeps re-asking for
  Accessibility / Screen Recording permissions. The build re-signs with a fixed
  `--identifier com.lwouis.alt-tab-macos` and an explicit identifier-based
  designated requirement, so TCC grants persist across fork updates. (Still
  unsigned — no Apple cert; just a deterministic ad-hoc identity.)
- **Notify Homebrew tap:** optional `repository_dispatch` to `Korel/homebrew-tap`
  if a `TAP_DISPATCH_TOKEN` secret is set. Unset by design; the tap also has its
  own daily cron, so the cask updates within ~24h regardless.

### `.github/workflows/ci_cd.yml` (neutralized)
This is **upstream's** production release pipeline (signs, notarizes, runs
`semantic-release`, publishes to upstream's Sparkle feed / website / AppCenter).
None of it works in a fork, so its trigger was changed from `on: push` to
`on: workflow_dispatch` so it never auto-fires. Kept (not deleted) to minimize
merge conflicts with upstream.

### `scripts/fork/apply_pro_unlock.sh`
Rewrites `LicenseManager.computeState()`'s body to `return .pro`. Notes:
- Replaces the **whole method body** (not an early return) because the project
  builds with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, where dead code after a
  `return` is a hard error.
- Matches the method by **signature + brace counting**, so it tolerates upstream
  edits elsewhere in the file. It is idempotent.
- **Fails loudly** if `computeState()` is renamed/removed, so the build breaks
  visibly instead of silently shipping a locked app. If that happens, update
  this script to match upstream's new licensing entry point.

## Homebrew install

The cask lives in a separate repo, `Korel/homebrew-tap` (casks must live in a
`homebrew-*` repo; modern Homebrew rejects loose `.rb` files and removed
install-by-URL and `--no-quarantine`). The cask pins `version` + `sha256`, has a
`postflight` that runs `xattr -dr com.apple.quarantine` (so the unsigned app
launches), and is bumped by that repo's `update-cask.yml` (daily cron + manual +
`repository_dispatch`).

```sh
brew install --cask Korel/tap/alt-tab-fork
```

The official `alt-tab` cask installs to the same `/Applications/AltTab.app`;
uninstall it first (`brew uninstall --cask alt-tab`) to use the fork build.

## First launch / permissions

Because the build is unsigned, the first install of a build with a new identity
may ask once for permissions. To make a manually-copied/installed app stick:

```sh
osascript -e 'quit app "AltTab"' 2>/dev/null
sudo codesign --force --deep \
  --identifier "com.lwouis.alt-tab-macos" \
  -r='designated => identifier "com.lwouis.alt-tab-macos"' \
  --sign - /Applications/AltTab.app
tccutil reset ScreenCapture com.lwouis.alt-tab-macos
tccutil reset Accessibility com.lwouis.alt-tab-macos
open /Applications/AltTab.app
```

CI applies this same stable-identifier re-sign automatically, so releases
installed via the cask shouldn't need it.
