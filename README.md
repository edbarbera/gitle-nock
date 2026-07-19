# gitle nock

A menu that hides in your MacBook's notch. Hover it, and you get plain-English buttons for saving your work and putting it online — no terminal, no git jargon.

Built for people meeting version control for the first time, usually because they started vibe coding and someone told them they needed git.

```
┌──────────────────────── the notch ────────────────────────┐
│  demo-project                                          ●  │
├───────────────────────────────────────────────────────────┤
│  main                                                     │
│  3 unsaved changes                                        │
│                                                           │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐    │
│  │ Save your     │ │ Send it       │ │ Grab the      │    │
│  │ work          │ │ online        │ │ latest        │    │
│  └───────────────┘ └───────────────┘ └───────────────┘    │
│                                                           │
│  See what changed   README.md, login.js, app.css          │
│                                                           │
│  </>  ▦  ↻  ⚙                                        ⏻   │
└───────────────────────────────────────────────────────────┘
```

## What it is

A thin UI shell over the [gitle](https://github.com/edbarbera/gitle) CLI. gitle already turns git into friendly verbs and carries the safety rails (secret detection, big-file warnings, the push-to-main nudge). This app puts those verbs in the notch.

| In the menu | gitle command | git underneath |
|---|---|---|
| Save your work | `gitle save --all "…"` | `add` + `commit` |
| Send it online | `gitle send` | `push` |
| Grab the latest | `gitle grab` | `pull --rebase` |

**Writes go through `gitle`. Reads go through `git` directly** — branch, changed files, ahead/behind counts. `gitle status` prints prose written for humans, and parsing it for UI state would break every time the wording is polished.

## Requirements

- macOS 13 or later (developed and tested on macOS 26)
- Xcode command line tools, for `swift build`
- [`gitle`](https://github.com/edbarbera/gitle) on your PATH:
  ```sh
  curl -fsSL https://raw.githubusercontent.com/edbarbera/gitle/main/install.sh | sh
  ```

A hardware notch is optional. Without one, the app draws a small pill at the top-centre of the screen instead — toggleable in Settings.

## Build and run locally

```sh
git clone <this repo>
cd gitle-nock
./scripts/bundle.sh          # builds release and wraps it in a .app
open build/GitleNock.app
```

The script runs `swift build`, assembles `build/GitleNock.app`, writes the `Info.plist`, and ad-hoc signs it. Pass `debug` for a debug build:

```sh
./scripts/bundle.sh debug
```

To iterate without the bundle (note: launched this way the app inherits your shell's file-access permissions, which differ from a real launch — see [Permissions](#permissions)):

```sh
swift build && .build/debug/GitleNock
```

To stop it:

```sh
pkill -f GitleNock
```

## Install

There is no installer or signed release yet. Build it, then:

```sh
./scripts/bundle.sh
cp -R build/GitleNock.app /Applications/
open /Applications/GitleNock.app
```

The app is ad-hoc signed, so on first launch macOS may refuse to open it. Right-click the app in Finder and choose **Open**, then confirm.

It runs as an accessory app: no Dock icon, no menu bar item. Its only presence is the notch. Quit it from the power icon in the menu footer, or from Settings.

## Using it

1. **First launch** opens Settings, because a notch with no projects can't do anything. Click **Add a project…** and pick the folder your work lives in.
2. **Hover the notch.** The menu drops down. Move away and it closes.
3. **Save your work** — describe what you changed in your own words. That's a commit.
4. **Send it online** — uploads to GitHub. If the project has no online copy yet, gitle offers to create one.
5. **Grab the latest** — pulls down everyone else's work.

The dot in the notch summarises the project at a glance:

| Dot | Meaning |
|---|---|
| 🟢 Green | Everything saved and sent |
| 🟠 Amber | You have unsaved changes |
| 🔵 Blue | Saved, but not in sync with online |
| ⚪️ Grey | No project selected, or not a git repo |

Footer icons, left to right: open in VS Code, switch project, refresh, settings, quit.

### Settings

- **Your projects** — add, remove, and switch. Folders that have gone missing are flagged rather than silently dropped.
- **Check for changes every** — how often the app re-reads git state (default 6 seconds).
- **Show a pill on screens without a notch** — off means the app is invisible on external displays.
- **Ask me before sending work online** — adds a confirmation step to Send.
- **Open gitle nock when I log in** — see Known limitations.
- **Setup** — where `gitle` and `git` were found, and which git account your saves are attributed to.

## Permissions

macOS gates `~/Documents`, `~/Desktop`, and `~/Downloads`. Picking a folder through **Add a project…** grants access to it; that is the intended path and the one to use.

If a project's folder is blocked, the menu says so and offers a **Give access** button rather than pretending the folder isn't set up. Re-picking the same folder restores access.

## Project layout

```
Sources/GitleNock/
├── App/
│   ├── main.swift                    entry point, accessory activation policy
│   ├── AppDelegate.swift             wires state, notch, settings window
│   ├── AppState.swift                the observable model everything reads
│   ├── Settings.swift                preferences, backed by UserDefaults
│   └── SettingsWindowController.swift
├── Notch/
│   ├── NotchGeometry.swift           where the notch is, or where to fake one
│   ├── NotchPanel.swift              borderless panel that can take key focus
│   └── NotchWindowController.swift   hover, expand/collapse, window level
├── Git/
│   ├── Shell.swift                   subprocess runner
│   ├── GitReader.swift               structured reads via plumbing git
│   ├── GitleRunner.swift             mutations via the gitle CLI
│   └── RepoStore.swift               the project list, persisted
├── Models/RepoModels.swift
└── UI/                               SwiftUI views
```

Two details worth knowing before you change things:

- **`Shell.run` drains stdout and stderr concurrently and has a timeout.** Reading one to EOF before the other deadlocks as soon as a child fills the pipe it isn't being read from. All subprocess work runs on a dedicated `DispatchQueue`, never Swift's cooperative pool, because blocking that pool starves the app.
- **`NotchRootView` states both frame dimensions outright.** Letting either side size to content makes the background and clip shape smaller than the laid-out content, which silently crops anything a `Spacer` pushes to the bottom.

## Testing without a cursor

Set `GITLENOCK_DEBUG=1` to enable a distributed-notification hook that drives the UI from a script — useful for screenshots and CI:

```sh
open build/GitleNock.app --env GITLENOCK_DEBUG=1
```

Then post `com.edbarbera.gitlenock.toggle` with an object of `addrepo`, `settings`, `editor`, or none at all to toggle the menu.

It is off by default on purpose: the notification is system-wide, so an always-on hook would let any process on the Mac pop this app's folder chooser.

## Known limitations

This is a prototype. Known gaps, in rough order of how likely you are to hit them:

- **Saving always includes every changed file.** `gitle save --all` skips the interactive file checklist, which can't be answered from a subprocess. Per-file selection belongs in the notch UI and isn't built yet — the "See what changed" screen is where it should go.
- **Launch at login likely fails on an ad-hoc signed build.** `SMAppService` generally refuses one. The error is surfaced in Settings rather than leaving a toggle that lies, but this needs a properly signed build to work.
- **VS Code only.** Cursor, Zed, and friends aren't detected. Adding them is a one-line change to `editorBundleIDs` in `AppState.swift`; a picker in Settings would be better.
- **GitHub sign-in isn't built.** The app uses whatever git account is already configured on the Mac.
- **Long-running `gitle` commands that need input will time out** after 20 seconds rather than prompting. Anything interactive still has to be done in a terminal.
- **The app polls.** No FSEvents watching, so changes show up within the refresh interval rather than instantly.
- **Not signed or notarised**, so distribution beyond your own Mac needs a Developer ID.

## Licence

Not yet chosen.
