# Task Manager for macOS

A native SwiftUI recreation of the Windows 11 Task Manager for macOS: Fluent styling, heat-mapped process
table, live performance graphs, and the same eight pages.

**Website and download: https://mr-who-root.github.io/macos-task-manager/**

## Install

```sh
curl -fsSL https://mr-who-root.github.io/macos-task-manager/install.sh | bash
```

The script downloads the latest release, verifies its SHA-256 checksum, installs it in `/Applications`
(or `~/Applications` if that isn't writable) and opens it. Or download `TaskManager.zip` from
[Releases](https://github.com/Mr-Who-Root/macos-task-manager/releases/latest), unzip it and drag the app to
Applications. The app isn't notarized, so on first launch use System Settings › Privacy & Security › Open Anyway.

Requires macOS 15 or later on Apple silicon or Intel.

## Updates

Task Manager checks GitHub Releases once a day (Settings › Updates, where you can also check by hand or turn
this off). When a newer version exists, a dot appears on Settings; **Download and install** fetches
`TaskManager.zip`, verifies its checksum, code signature, bundle identifier and version, then replaces the
app and relaunches it.

## Pages

| Page | What it shows |
| --- | --- |
| **Processes** | Apps, background processes and macOS processes, grouped with their helper processes. Heat-mapped CPU / Memory / Disk / Network cells, header totals, sortable and resizable columns, optional Publisher / PID / Process name / User / Threads / Architecture columns (right-click the header). |
| **Performance** | CPU (overall or per logical processor, optional kernel time), Memory (with composition bar), each Disk, each network adapter, and GPU, all with 60-sample graphs. |
| **Temperatures** | CPU performance and efficiency cores, GPU, SoC, memory, SSD, battery, Wi-Fi, airflow and power-delivery sensors (average, hottest, min/max, history) plus fan speeds and thermal pressure. |
| **App history** | CPU time, network and disk usage per app, recorded while Task Manager runs and saved between launches. |
| **Startup apps** | Login items plus third-party launch agents and daemons, with publisher (from the code signature), status and enable/disable. |
| **Users** | Per-account totals, expandable to that account's apps. |
| **Details** | Every process: PID, status, user, CPU, CPU time, memory, threads, architecture (Rosetta shows as x64), priority and path. |
| **Services** | launchd services in the user and system domains, with start / stop / restart. |
| **Settings** | Start page, update speed (High / Normal / Low / Paused), theme, always on top, menu-bar CPU meter, global shortcut. |

Actions work the way they do on Windows: **End task** (`Delete` / `⌘⌫`), Force end task, **Efficiency mode**
(Darwin background priority, shown with a leaf), Suspend / Resume, Set priority, End process tree, Open file
location, Search online, Properties, and **Run new task** (`⌘N`), which also understands `notepad`, `calc`, `cmd`
and similar Windows names.

**Control-Shift-Escape** brings Task Manager to the front from any app. Finder can't be ended, only
**restarted**, the way Windows Explorer works in Windows Task Manager.

## Designs

Settings › Design switches the whole look, with a preview of each:

- **Windows 11**: Fluent, Mica and a navigation rail
- **Windows 10**: flat, with tabs across the top
- **macOS**: a source-list sidebar and the system accent colour
- **Midnight**: deep blue glass with neon graphs (always dark)
- **Terminal**: green phosphor on black, in a monospaced font (always dark)

Pick an accent colour, or keep the design's own.

## Menu bar

Settings › Menu bar adds any of **CPU, Memory, GPU, Network, Disk and Temperature** to the menu bar, shown as
icon and value, value only, a mini graph or a meter. Click one for a pop-over with a live graph, details and the
busiest apps. Command-drag an item out of the menu bar to remove it. Task Manager keeps running in the menu bar
while any item is shown.

## Widgets

Add them from the widget gallery (desktop or Notification Center): **CPU**, **Memory**, **System** (small,
medium, large), **Top Apps**, **Temperatures**, **Network** and **Storage**. They follow the chosen design, and
clicking one opens the matching page. While Task Manager runs it shares live figures with its widgets; when it
isn't running, the widgets measure CPU, memory, disk and network themselves, and the process and temperature
widgets ask you to open the app.

## Build from source

Requires Xcode (or the Swift 6 toolchain).

```sh
./scripts/build-app.sh             # builds build/Task Manager.app
open "build/Task Manager.app"

./scripts/build-app.sh --install   # also copies it to /Applications
./scripts/build-app.sh --universal # Apple silicon + Intel binary
```

For quick iteration during development, `swift run` also works.

## Releasing

1. On `dev`, bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist`, open a PR and merge it into `main`.
2. On an up-to-date `main`, run `scripts/release.sh [notes.md]`.

The script builds a universal app, packages `TaskManager.zip` with `TaskManager.zip.sha256`, tags `vX.Y.Z`,
pushes the tag and creates the GitHub release. The website's download button, `install.sh` and the in-app
updater all use the latest release's `TaskManager.zip`, so keep those asset names.

The website lives in `docs/` and is served by GitHub Pages from the `main` branch.

## Permissions and limits

- macOS hides other users' processes (mostly `root`) from regular apps. Task Manager gets their CPU and memory
  from `/bin/ps` instead, so their memory is resident size rather than footprint, and their disk I/O isn't available.
- Ending, prioritising or applying efficiency mode to another user's process asks for an administrator password.
  Task Manager refuses to end `kernel_task` and `launchd`.
- The Startup apps page reads login items through System Events, so macOS asks once for Automation permission.
- Per-process network usage comes from `nettop` and only counts open connections.
- Apple silicon doesn't expose the current CPU frequency, so the Performance page shows each cluster's maximum.
- Temperatures come from the SMC and the HID sensor hub, which macOS doesn't document; Task Manager only reads
  them. Cores that are powered down don't report a temperature and show as Idle.
- The widget extension is sandboxed. Its only file access is read-only access to
  `~/Library/Application Support/TaskManager/`, where the app writes `widget-snapshot.json`.
- macOS has no per-process GPU accounting, so there is no GPU column on the Processes page.

## Layout

```
Sources/TaskManager/
  App/        entry point, menu commands, app delegate, debug-only UI test hooks
  Core/       samplers (libproc, sysctl, IOKit, SMC/HID sensors, routing socket), grouping, launchd, actions, updater
  Model/      Monitor (sampling + history), settings, UI state, app history, widget publisher
  UI/         window shell, designs and tokens, heat table, graphs, menu bar, pages, dialogs
Sources/TaskManagerWidgets/   WidgetKit extension (packaged as Contents/PlugIns/TaskManagerWidgets.appex)
Sources/TaskManagerShared/    the snapshot model shared by the app and its widgets
scripts/      build-app.sh, release.sh, make-icon.swift
docs/         website (GitHub Pages) and install.sh
```
