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
│  </>  ▦  ↻  ⚙                                        ⏻    │
└───────────────────────────────────────────────────────────┘
```

## What it is

A notch-sized front end for the same job the [gitle](https://github.com/edbarbera/gitle) CLI does: turning git into plain-English verbs, with safety rails in front of the sharp edges.

| In the menu     | What runs    | git underneath                                  |
| --------------- | ------------ | ----------------------------------------------- |
| Save your work  | app          | `add` + `commit`                                |
| Send it online  | app          | `push`                                          |
| Grab the latest | `gitle grab` | `pull --rebase`                                 |
| Sort it out     | app          | `checkout --ours/--theirs`, `rebase --continue` |
| Set it up       | app          | `init`, `config`                                |
| Go back / undo  | app          | `reset`, `clean`                                |

**Reads go through `git` directly** — branch, changed files, ahead/behind counts. `gitle status` prints prose written for humans, and parsing it for UI state would break every time the wording is polished.

**Writes mostly go through `git` too, and the app owns the safety rails.** This is deliberate, and it wasn't the original plan. Almost every gitle command pauses on a terminal prompt — the file checklist, "save these anyway?", "send to main anyway?", "are you sure?". A prompt can't be answered from a headless subprocess: gitle correctly falls back to its safe default, which means the action doesn't happen. Run from the notch, that made _sending to `main` fail every time_ and _saving fail outright whenever a `.env` was present_, with no explanation either time.

So the notch asks those questions itself, in the panel, and then runs the underlying git command. The checks are ported in [`SafetyRails.swift`](Sources/GitleNock/Git/SafetyRails.swift) and kept deliberately in step with gitle's `cmd/safety.go` and `cmd/gitignore.go` — same secret globs, same 10 MB threshold, same protected branches, same `.gitignore` templates.

`gitle grab` is the exception and still runs as the CLI: it has no prompts, so it works headless exactly as it does in a terminal.

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
3. **Save your work** — tick which files to include (everything's ticked already), then describe what you changed in your own words. That's a commit.
4. **Send it online** — uploads to GitHub. If the project has no online copy yet, you're asked for a link to one.
5. **Grab the latest** — pulls down everyone else's work.

If the folder isn't set up for git at all, the menu offers **Set it up** instead: name and email, a `.gitignore` matched to the project, and a first save.

### The steps that stop and ask

Anything that could lose work or leak something asks first, in the panel:

| Situation                                | What you see                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------------------ |
| Files to include in a save               | A checklist, everything pre-ticked. Untick what should wait.                   |
| A `.env`, `*.pem`, `id_rsa`… in the save | **Worth a second look** — leave them out, or save anyway.                      |
| A file over 10 MB                        | Same screen, flagged separately.                                               |
| Sending straight to `main`/`master`      | What that means, and that it's fine when working alone.                        |
| Two people changed the same lines        | **Sort it out** — per file, keep either version or open it and fix it by hand. |
| Throwing away unsaved changes            | Every affected file listed, with _Keep my changes_ as the easy option.         |

The dot in the notch summarises the project at a glance:

| Dot      | Meaning                                |
| -------- | -------------------------------------- |
| 🟢 Green | Everything saved and sent              |
| 🟠 Amber | You have unsaved changes               |
| 🔵 Blue  | Saved, but not in sync with online     |
| ⚪️ Grey  | No project selected, or not a git repo |

Footer icons, left to right: open in VS Code, switch project, go back / undo, refresh, settings, quit.

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
│   ├── GitWriter.swift               mutations via git, once the panel has asked
│   ├── SafetyRails.swift             secret/big-file checks, .gitignore starters
│   ├── GitleRunner.swift             `gitle grab`, the one prompt-free command
│   └── RepoStore.swift               the project list, persisted
├── Models/RepoModels.swift
└── UI/
    ├── FlowViews.swift               the screens that stop and ask
    └── …                             SwiftUI views
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

- **The safety rails are duplicated, not shared.** `SafetyRails.swift` re-implements gitle's `cmd/safety.go` and `cmd/gitignore.go` in Swift. Change the globs or the size threshold in one repo and the other drifts. The proper fix is a non-interactive contract in gitle — a `--only <paths>` flag, a `--yes` to say the human already answered, and structured output so the notch renders warnings from data instead of re-deriving them.
- **`gitle` is barely used now** — only `grab`. The app is no longer a shell over the CLI, whatever the name suggests.
- **No AI-drafted save messages.** `gitle save --ai` exists; the notch doesn't offer it.
- **Conflict resolution is whole-file only.** gitle's `--advanced` mode goes section by section within a file; here it's keep-one-side or open the file yourself.
- **Launch at login likely fails on an ad-hoc signed build.** `SMAppService` generally refuses one. The error is surfaced in Settings rather than leaving a toggle that lies, but this needs a properly signed build to work.
- **VS Code only.** Cursor, Zed, and friends aren't detected. Adding them is a one-line change to `editorBundleIDs` in `AppState.swift`; a picker in Settings would be better.
- **GitHub sign-in isn't built.** The app uses whatever git account is already configured on the Mac.
- **Subprocesses time out after 20 seconds.** A slow push over a bad connection can hit that.
- **The app polls.** No FSEvents watching, so changes show up within the refresh interval rather than instantly.
- **Not signed or notarised**, so distribution beyond your own Mac needs a Developer ID.

## Licence

Not yet chosen.

