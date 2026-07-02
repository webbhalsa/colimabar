# ColimaBar

A native macOS menu bar controller for [colima](https://github.com/abiosoft/colima). Start and stop your Colima VMs from the menu bar, watch VM and Docker disk usage, reclaim disk space with one click, and manage multiple profiles from a Settings window.

## Installation

```bash
brew install --cask webbhalsa/tap/colimabar
```

Colima itself is a declared cask dependency and will be installed automatically if missing.

Because the app is currently **ad-hoc signed**, macOS Gatekeeper will block it on first launch. Either right-click `ColimaBar.app` in Finder and choose Open, or clear the quarantine flag once:

```bash
xattr -d com.apple.quarantine /Applications/ColimaBar.app
```

To upgrade:

```bash
brew upgrade --cask colimabar
```

---

## The menu bar icon

A small llama carrying three Docker container boxes lives in your menu bar. The llama silhouette uses the default menu bar tint; the cargo boxes are the state indicator:

| Cargo color | Meaning                                                                 |
|-------------|-------------------------------------------------------------------------|
| Green       | At least one profile is running                                         |
| Orange      | An operation is in progress, or a status transition was just detected   |
| Red         | Colima binary is missing                                                |
| Gray        | All profiles stopped                                                    |

Clicking the icon opens a native menu with per-profile Start / Stop / Restart, plus a Show Progress link when an operation is running.

---

## Features

- **Streaming progress HUD** — start / stop / restart / prune all run in a floating window that shows colima's live output line by line, with a collapsible full log
- **Per-profile Settings** — sliders for CPU, memory, disk; picker for runtime (`docker` / `containerd` / `incus`). Apply stops and restarts the VM with the new configuration
- **New / delete profiles** — small `+` in the Settings sidebar opens a create sheet; each profile has a Danger zone with confirmation-guarded delete
- **VM disk usage bar** — reads `df -k /mnt/lima-colima` inside the VM every 30 seconds. Colored green / orange / red at 70% / 90%
- **Docker breakdown** — parses `docker system df` and shows Images / Containers / Volumes / Build Cache side by side, with a Reclaim button that runs `docker system prune -f` (volumes and tagged images are preserved)
- **Launch at login** — via `SMAppService.mainApp`, togglable from General settings
- **Per-profile auto-start** — mark any profile to start automatically when ColimaBar launches

Multiple profiles can run concurrently (they each get their own VM and Docker socket at `~/.colima/<name>/docker.sock`). The menu bar icon reflects the aggregate — green if any profile is running.

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel
- Colima 0.7+ (installed automatically as a cask dependency)

---

## Building from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/webbhalsa/colimabar.git
cd colimabar

make run          # build (Debug, ad-hoc signed) and launch
make relaunch     # kill running instance, rebuild, launch — dev loop
make typecheck    # swiftc type-check only, no Xcode.app needed
make release      # Release build + .zip + sha256
make clean        # remove build/ and the generated .xcodeproj
```

The Xcode project is generated from `project.yml` on every build; don't edit `ColimaBar.xcodeproj` directly.

---

## How it works

- Pure SwiftUI targeting macOS 14+, no third-party dependencies
- Wraps the `colima` CLI: `Process` is spawned per command, stdout and stderr flow back through `AsyncThrowingStream<String, Error>` line by line
- Status is polled every 2 seconds via `colima list --json`. Between polls, any observed status change briefly flashes the icon orange so terminal-triggered `colima start/stop` still gives visual feedback
- Disk usage and docker breakdown poll every 30 seconds via `colima ssh -p <profile> -- <cmd>`
- The menu bar icon is composited at runtime — the llama silhouette and the cargo mask are separate template PNGs; they get tinted and merged into a non-template `NSImage` with `isTemplate = false`. Without this, `MenuBarExtra` re-templates SwiftUI content and strips the state color

---

## Releasing a new version

```bash
git tag v0.1.0
git push origin v0.1.0
```

The [Release workflow](.github/workflows/release.yml) builds an ad-hoc-signed macOS `.app`, zips it, creates a GitHub Release, and pushes an updated `colimabar.rb` cask to [webbhalsa/homebrew-tap](https://github.com/webbhalsa/homebrew-tap) using the `HOMEBREW_TAP_GITHUB_TOKEN` secret.

Tags must be semver-prefixed with `v` (e.g. `v0.1.0`).

---

## Known limitations

- **Ad-hoc signed** — see the Gatekeeper workaround at the top. A future release will be Developer ID signed and notarized.
- **No transitional `Starting` / `Stopping` state** — `colima list --json` only reports `Running` and `Stopped`; the icon flashes orange after the fact when a change is detected between polls, rather than during the operation itself.
- **Bundle path is baked in when registering for launch-at-login** — if you `make clean` after enabling launch-at-login, the login item points at a missing path. Re-toggle from General settings after rebuilding.
