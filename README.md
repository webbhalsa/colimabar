# ColimaBar

A native macOS menu bar controller for [colima](https://github.com/abiosoft/colima). Start and stop your Colima VMs from the menu bar, watch VM and Docker disk usage, reclaim disk space with one click, and manage multiple profiles from a Settings window.

## Installation

```bash
brew install --cask webbhalsa/tap/colimabar
```

Colima itself is a declared cask dependency and will be installed automatically if missing.

Because the app is currently **ad-hoc signed**, macOS Gatekeeper will block it on first launch with a "cannot verify … free of malware" dialog (only Close / Move to Bin — Apple removed the older right-click Open workaround in Sequoia). Clear the quarantine flag once and open normally:

```bash
xattr -d com.apple.quarantine /Applications/ColimaBar.app
open /Applications/ColimaBar.app
```

Or, from **System Settings › Privacy & Security**, scroll to the bottom and click **Open Anyway** next to ColimaBar.

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

Clicking the icon opens a native menu with per-profile Start / Stop / Restart / Open Terminal…, plus a Show Progress link when an operation is running. When a ColimaBar update is available, a small red dot appears on the llama and an "Update to vX" item appears at the top of the dropdown.

---

## Features

- **Streaming progress HUD** — start / stop / restart / apply / prune / create / delete all run in a floating window that shows colima's live output line by line, with a collapsible full log
- **Per-profile Settings** — sliders for CPU, memory, disk; picker for runtime (`docker` / `containerd` / `incus`). Apply stops and restarts the VM with the new configuration
- **New / delete profiles** — small `+` in the Settings sidebar opens a create sheet (name pre-filled to `default` when starting fresh); each profile has a Danger zone with confirmation-guarded delete
- **First-run onboarding** — when colima has no profiles yet, the menu shows "Start your first profile…" and General gets a Get Started section, both opening the New Profile sheet with sensible defaults (4 CPU, 8 GB, 100 GB, docker)
- **VM disk usage bar** — runtime-aware `df` inside the VM (measures the docker/containerd/incus data root). Bar tints green / orange / red at 70% / 90%. Local macOS notification fires when a profile crosses 90% (throttled to once per 6 hours per profile)
- **Docker breakdown with expandable detail** — Images / Containers / Volumes / Build Cache. Each row expands to a live list of items with per-item action icons (below). Item lists reload on every expand, so external `docker run/pull/create` shows up
- **Per-container actions** — start / stop / restart / shell into container / view live logs / inspect (`docker inspect` JSON in a floating window) / remove. Shell-into opens Terminal already `docker exec -it <id>`-ed with bash-then-sh fallback
- **Live container stats** — inline CPU% and Mem% per container, polled every 3s while the container list is expanded
- **Port pills** — published ports appear as clickable capsules under each container name. Left-click copies the host port; right-click adds Copy URL and Open in Browser for HTTP-ish ports
- **Reclaim + Deep prune** — two buttons at the bottom of the Docker section: **Reclaim** runs `docker system prune -f` (safe), **Deep prune…** runs `docker system prune -a --volumes -f` behind a destructive confirmation dialog. Footer shows what each button would recover
- **Docker daemon info** — collapsible section per running profile with server version, storage / cgroup / logging drivers, kernel, root dir, insecure registries, and mirrors
- **Colima config viewer** — see the raw `~/.colima/<name>/colima.yaml` inline in Settings, with a Reveal-in-Finder button for editing
- **Multi-runtime aware** — profiles running `containerd` or `incus` hide the docker-specific sections; disk usage measures the correct runtime root
- **Container logs viewer** — floating window streaming `docker logs -f --tail 500` with auto-scroll toggle, line count, and Clear
- **Open Terminal in VM** — menu bar dropdown per running profile writes a temp `.command` file that opens Terminal.app already SSH'd into the VM
- **Copy DOCKER_HOST** — per running profile, both from the menu and next to the socket path in Settings — copies `export DOCKER_HOST=unix://…` ready to paste
- **Colima version + upgrade hint** — General settings shows the installed colima version and flags when a newer release is available on `abiosoft/colima`, with a `brew upgrade colima` hint
- **In-app update check** — polls `webbhalsa/colimabar/releases/latest` every 6 hours; when a newer version exists, a red dot appears on the menu bar icon and next to General in the sidebar, plus a full notice with the `brew upgrade --cask colimabar` command in General. A "Skip this version" link persists the skipped version in `UserDefaults`
- **Launch at login** — via `SMAppService.mainApp`, togglable from General settings
- **Per-profile auto-start** — mark any profile to start automatically when ColimaBar launches (sequential start when multiple)
- **Resizable Settings window** — drag any edge to fit long image / volume names on one line; names are text-selectable even when middle-truncated

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
- Wraps the `colima` CLI: `Process` is spawned per command with an explicit PATH including `/opt/homebrew/bin` (LaunchServices otherwise strips it and colima can't find `limactl`). stdout and stderr flow back through `AsyncThrowingStream<String, Error>` line by line
- Status is polled every 2 seconds via `colima list --json`. Between polls, any observed status change briefly flashes the icon orange so terminal-triggered `colima start/stop` still gives visual feedback
- Disk usage and docker breakdown poll every 30 seconds via `colima ssh -p <profile> -- <cmd>` (also on-demand via the Refresh menu item)
- Docker detail lists (images / containers / volumes) load lazily when their disclosure row is expanded, and re-fetch on every re-expand so external CLI actions don't leave stale views
- The menu bar icon is composited at runtime — the llama silhouette and the cargo mask are separate template PNGs; they get tinted and merged into a non-template `NSImage` with `isTemplate = false`. Without this, `MenuBarExtra` re-templates SwiftUI content and strips the state color. Update badges are painted as a red dot in the same composite
- Terminal-in-VM writes a temporary `.command` script to `/tmp/` and hands it to `NSWorkspace.open()`. Avoids needing Automation permissions that `NSAppleScript` would trigger

---

## Releasing a new version

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The [Release workflow](.github/workflows/release.yml) builds an ad-hoc-signed macOS `.app`, zips it, creates a GitHub Release, and pushes an updated `Casks/colimabar.rb` cask to [webbhalsa/homebrew-tap](https://github.com/webbhalsa/homebrew-tap) using the `HOMEBREW_TAP_GITHUB_TOKEN` secret.

Tags must be semver-prefixed with `v` (e.g. `v0.1.7`).

---

## Known limitations

- **Ad-hoc signed** — see the Gatekeeper workaround at the top. A future release will be Developer ID signed and notarized.
- **No transitional `Starting` / `Stopping` state** — `colima list --json` only reports `Running` and `Stopped`; the icon flashes orange after the fact when a change is detected between polls, rather than during the operation itself.
- **Bundle path is baked in when registering for launch-at-login** — if you `make clean` after enabling launch-at-login, the login item points at a missing path. Re-toggle from General settings after rebuilding.
