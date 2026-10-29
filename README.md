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
| **Processes** | Apps, background processes and macOS processes, grouped with their helper processes. Heat-mapped CPU / Memory / Disk / Network cells, header totals, sortable and resizable columns, optional Publisher / PID / Process name / User / Threads / Architecture / Power usage / Power usage trend columns (right-click the header). **Map** shows the same apps as a treemap sized by memory, CPU, power or network; double-click an app to see its processes. Apps that stop responding are marked **Not responding**, with End task, Wait and a saved sample of what they were doing. |
| **Performance** | CPU (overall or per logical processor, optional kernel time), Memory (with composition bar), each Disk, each network adapter, and GPU, all with 60-sample graphs. |
| **Timeline** | Rewind: CPU, memory, disk, network and power for the last hour, 6 hours or 24 hours. Hover over the graph to see any minute, click to keep it, and see which apps were behind it, plus events such as apps that stopped responding. Jump to the biggest moments. |
| **Temperatures** | CPU performance and efficiency cores, GPU, SoC, memory, SSD, battery, Wi-Fi, airflow and power-delivery sensors (average, hottest, min/max, history) plus fan speeds and thermal pressure. |
| **Battery** | Charge, time remaining and charge rate; whole-Mac power draw; health (maximum capacity, cycle count, condition); battery temperature; the power adapter; battery level and power draw over the last 24 hours; battery usage by app (power now, two-minute trend, energy used, idle wake-ups); and which apps are preventing sleep. |
| **App history** | CPU time, network, disk and energy usage per app, recorded while Task Manager runs and saved between launches. **Data usage** shows what each app downloaded and uploaded today, in the last 7 days and in the last 30 days, and highlights big uploaders. |
| **Privacy** | Which apps are using the camera, microphone, screen recording and location right now and over the last 24 hours (the apps behind the menu bar's privacy indicators), and which apps are listening for network connections. |
| **Startup apps** | Login items plus third-party launch agents and daemons, with publisher (from the code signature), status and enable/disable. |
| **Users** | Per-account totals, expandable to that account's apps. |
| **Details** | Every process: PID, status, user, CPU, CPU time, memory, threads, architecture (Rosetta shows as x64), priority and path. |
| **Services** | launchd services in the user and system domains, with start / stop / restart. |
| **Settings** | Start page, update speed (High / Normal / Low / Paused), theme, always on top, menu-bar CPU meter, global shortcut. |

**Why is my Mac slow?** (`⌘D`, or the button on Processes, Performance and Timeline) looks at what's happening and explains it in plain words: apps that stopped responding, apps hogging the CPU, low memory, a full or busy disk, overheating, Spotlight, Time Machine, Photos or iCloud working in the background, Low Power Mode, a long uptime and big uploads. Each finding comes with a fix, such as End task, Efficiency mode or the right System Settings pane.

Actions work the way they do on Windows: **End task** (`Delete` / `⌘⌫`), Force end task, **Efficiency mode**,
Suspend / Resume, Set priority, End process tree, Open file location, Search online, Properties, and **Run new
task** (`⌘N`), which also understands `notepad`, `calc`, `cmd` and similar Windows names.

**Efficiency mode** puts a process at macOS background priority: lowest CPU priority, efficiency cores, and
throttled disk and network I/O. Task Manager asks before turning it on (Settings › Other options turns the question
off), marks those processes with a green leaf and "Efficiency mode" in the Status column, and shows an
"N in efficiency mode" badge on the Processes page that filters to them. Avoid it for apps you're actively using,
such as browsers: they stop feeling smooth. Click Efficiency mode again, or quit and reopen the app, to undo it.

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

Add them from the widget gallery (desktop or Notification Center). Sixteen widgets, most in several sizes:

| Group | Widgets |
| --- | --- |
| **Resources** | **CPU**, **Memory**, **Temperatures** and **Network** (small, medium, large), **GPU** and **Storage** (small, medium), **System** (small, medium, large) and **Top Apps** (medium, large) |
| **Battery** | **Battery** (charge, time left, the last 24 hours and the apps using the most power), **Battery Usage**, **Power Draw**, **Battery Health** and **Preventing Sleep** |
| **Mixed** | **At a Glance** (CPU, memory, battery and temperature in a small widget), **Performance** (live graphs for CPU, memory, GPU, network, disk and power) and **Dashboard** (everything at once, large or extra large) |

They follow the chosen design, and clicking one opens the matching page. While Task Manager runs it shares live
figures with its widgets; when it isn't running, the widgets measure CPU, memory, disk, network and the battery's
charge themselves, and the process, sensor and power widgets ask you to open the app.

## Build from source

Requires Xcode (or the Swift 6 toolchain).

```sh
./scripts/build-app.sh             # builds build/Task Manager.app
open "build/Task Manager.app"

./scripts/build-app.sh --install   # also copies it to /Applications
./scripts/build-app.sh --universal # Apple silicon + Intel binary
```

For quick iteration during development, `swift run` also works. Run the tests with `swift test`.

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
- Per-app power is the CPU energy macOS accounts to each process, which Apple silicon reports and Intel Macs
  don't. On Intel Macs, and for other users' processes, Power usage is estimated from CPU use instead.
- Battery figures come from IOPowerSources and the battery driver. Whole-Mac power draw comes from the power
  telemetry Apple silicon laptops report; elsewhere it's the battery's discharge rate, so it's only shown on
  battery power. The 24-hour chart is recorded once a minute while Task Manager runs.
- Preventing sleep lists apps' power assertions (`pmset -g assertions`), leaving out powerd's own.
- The Privacy page reads the same log Control Center uses for the menu bar's camera, microphone, screen
  recording and location indicators (`log stream`, no extra permission). It lists your own apps' listening
  ports; system services run as other users and only an administrator can inspect them.
- An app is **Not responding** when WindowServer has flagged it (the spinning pointer) or its main thread has
  been fully busy for 5 seconds. A sample of what it was doing is saved to `~/Library/Logs/TaskManager/Hangs`
  (the 20 newest are kept).
- The Timeline is recorded once a minute while Task Manager runs and keeps 24 hours. Data usage keeps 31 days
  and, like the Network column, counts open connections only.

## Layout

```
Sources/TaskManager/
  App/        entry point, menu commands, app delegate, debug-only UI test hooks
  Core/       samplers (libproc, sysctl, IOKit, SMC/HID sensors, battery and power, routing socket), hang detection, listening ports, treemap layout, grouping, launchd, actions, updater
  Model/      Monitor (sampling + history), settings, UI state, app history, battery log, timeline, data usage, privacy monitor, diagnosis, widget publisher
  UI/         window shell, designs and tokens, heat table, graphs, menu bar, pages, dialogs
Sources/TaskManagerWidgets/   WidgetKit extension (packaged as Contents/PlugIns/TaskManagerWidgets.appex)
Sources/TaskManagerShared/    the snapshot model shared by the app and its widgets
Tests/TaskManagerTests/       unit tests (swift test)
scripts/      build-app.sh, release.sh, make-icon.swift
docs/         website (GitHub Pages) and install.sh
```
