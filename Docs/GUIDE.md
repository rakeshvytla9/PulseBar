# PulseBar 4.4

A native macOS menu bar control center modeled on Omarchy's current shell panels.
Requires macOS 13 or newer. Build locally with Apple’s Swift Command Line Tools; no third-party packages are required.

Open `PulseBar.app` and click the compact ↑/↓ item. Click a module for its controls
and detailed metrics. Customize is a native macOS button. It opens theme,
interface, unit, menu-bar, login and shortcut preferences. Right-click the menu
bar item for Control Center, Customize or Quit. Reopening the app also opens the
panel. Escape closes it; Tab navigates controls.

Each menu bar item is a separate native macOS status item. macOS manages spacing;
hold Command and drag items to reorder them on Sequoia. Customize → Menu bar items
can hide any item, or add sound, display, CPU and memory. The battery
percentage uses the native menu bar font and automatic status-item sizing, with
Apple’s own battery level and powered-battery symbols. The bolt remains visible
when connected to an adapter at 100%; the details distinguish Plugged in from
Charging. IOKit power-source notifications update the icon immediately. There is no custom battery drawing
or fixed-width percentage image.

Control center tiles can be hidden independently. Media, weather and world
clocks start hidden. Global Command-Control-A/N/D/P shortcuts are opt-in.
Move your built app to `/Applications/PulseBar.app` before enabling Launch at login
in Customize. Startup uses macOS SMAppService. Keep one installed copy to avoid
duplicate widgets and permission prompts.

## Omarchy parity

The home panel is 408 points wide and adjusts its height to visible tiles, with no large speed cards: speeds remain in
the footer. Display brightness and sound volume sit at the bottom. CPU/RAM values
and battery percentage are visible on the System and Power tiles. The date opens
Calendar.

The default appearance is neutral translucent **macOS Glass**, following your
system appearance. Panels have compact margins and different heights suited to
their content, rather than reserving a large empty area. Classic Tokyo Night,
Gruvbox, Everforest and Catppuccin remain optional in Customize.

The app bundles **JetBrainsMono Nerd Font**, including Nerd Font glyphs. Regular
and Bold are registered for this process only; nothing is copied into user or
system font folders. The app retains Omarchy's font and dedicated module pattern, with native rounded
glass surfaces by default.

Read [OMARCHY-FUNCTIONS.md](../OMARCHY-FUNCTIONS.md) for every supported function and
where macOS needs a settings handoff. In particular, this app does not claim to
replace the macOS window manager or provide a PipeWire-style per-app mixer.

## Wi-Fi and copying

Wi-Fi is connection-first: radio, current network, nearby networks, password
join and disconnect. A fresh scan starts on every opening, with automatic rescans every ten seconds
while the list stays open. Refresh also rescans on request. Traffic graphs and IP/DNS/signal attributes are in the separate Traffic
panel. Network names may need macOS Location permission on first use.

Click a metric value to copy it, or use the panel's copy button for a text summary.
A short Copied indicator confirms the write. Passwords are never included.

To hide duplicate Apple Wi-Fi and battery icons, use System Settings → Control
Centre. Apple’s built-in Control Centre remains available.

## Privacy and resource use

No packages, drivers, daemons, Homebrew, pip, or global libraries are required.
One coalescible timer samples 64-bit network counters every second. Visible CPU, memory,
battery, Wi-Fi details and relevant display controls refresh every second. Opening
or switching a panel requests fresh readings immediately, including per-core CPU
and battery power details. Background system readings stay at five seconds;
battery registry reads stay at 30 seconds when Power is closed and update every
second while Power is visible. All sampling uses the existing shared timer.
The one-second footer has its own observable state. Traffic cards and graph also
have their own observable model, so a one-second traffic tick does not invalidate
the surrounding controls or dashboard. Up to four recent panels retain their view trees in a bounded memory cache.
Hidden panels coalesce shared model changes into a dirty flag, with one refresh
when reopened. Weather/media state is shared across cached pages. The closed panel
receives no periodic metric publications. Reopening the same module reuses
the existing layout, immediately reads current metrics, and skips unchanged publications. Window size and position
are applied together only if the target frame changed. Data refresh precedes
layout; switching pages resizes an empty container before attaching the target
view, avoiding a layout of the old page at the new page's dimensions. Automatic
SwiftUI min/ideal/max size probes are disabled because AppKit supplies exact bounds. Login-item status is queried
when opening Customize, rather than on every popup opening. Wi-Fi scans run on each opening and every ten seconds while its list is visible;
the previous list remains usable while the asynchronous scan finishes. An in-flight
scan or connection is never duplicated.

Core Audio property listeners run only while home/audio controls are visible,
with coalesced events and no audio-device polling. Volume and brightness writes
update cached values without re-enumerating devices/displays on every slider
movement. Displays refresh every second while relevant panels
are visible. Custom menu bar images are rasterized once per changed value, static
symbols are cached, and battery text is laid out by the native status item. Polling pauses during sleep; history is bounded to 60 seconds.

Wi-Fi scanning happens on opening Wi-Fi, every ten seconds while visible, or Refresh; joining and media actions happen on request.
macOS may ask for Location access for Wi-Fi names, or Automation access for Music/Spotify. A rebuilt ad-hoc-signed app can require permissions again; grant them to the final installed copy. Weather sends the typed city to
Open-Meteo only after Load forecast; no GPS lookup or automatic weather polling
occurs. Passwords are passed directly to CoreWLAN and are not logged or saved.

## Ping and internet health

A real non-privileged IPv4 ICMP ping runs automatically every two seconds while
a panel is visible and every 30 seconds in the background, with
latency shown beside upload/download in the panel footer. Click the latency to
open Connection Quality: current and average latency, jitter, packet loss across
the last 20 probes, and current/last observed outage duration. Individual values
and the panel summary can be copied. Explanations and formulas are available from
the small ⓘ buttons instead of taking up space in the metrics cards. Jitter is the mean absolute RTT change
between adjacent successful probes; a lost probe breaks that pair. Outages are
observed at probe cadence, rather than claiming an exact link-failure timestamp.
Traffic has matching Download, Upload and Ping cards; the Ping card opens Connection
Quality. A labeled accent-colored Ping shortcut also stays beside footer speeds,
and Connection details includes a Connection Quality entry. There is no manual
ping form. The default target is 1.1.1.1.
Opening a panel requests fresh probes immediately. Network.framework verifies
TLS to `one.one.one.one:443`, falling back to `dns.google:443` if it fails. TLS
checks run every five seconds while a panel is visible and every 30 seconds in
the background. Ping and TLS have independent schedules, so a slow TLS timeout
does not delay the next ping. In-flight probes are never duplicated. Customize → Detect internet outages disables all
automatic health checks. No polling subprocesses, libraries or helpers are used.

Two consecutive failed rounds against both TLS destinations report Internet not
reachable. No route reports offline immediately. Wi-Fi association is shown
separately, so a known local connection can still be marked as lacking internet.
The Wi-Fi menu icon gains an exclamation mark in those states. A blocked ICMP
reply alone never declares an internet outage. These probes do not prove every
website/service works or identify all captive portals. Traffic counters alone
are never treated as proof of internet access. Checks pause during system sleep.

Bluetooth and AirDrop were removed because they did not offer sufficient additional
functionality over macOS controls. PulseBar no longer queries Bluetooth or links its device-control frameworks.
Focus and Screen Mirroring shortcuts were removed after checking in-place support:
Apple’s public Focus API is for app filters, and its mode-control service rejected
this app’s unprivileged query. AVKit’s public AirPlay picker controls media playback;
it is not a full system-screen mirroring selector. Apple Control Center remains
available for those functions. No Accessibility permission is requested by PulseBar.

## Measurement definitions

Speeds use decimal units (1000 B = 1 KB; eight bits = one byte) and actual elapsed
time. Automatic mode follows the primary physical route, including underlying
VPN traffic. Local-network data and protocol overhead are included. Interface
activity does not establish internet reachability. Session totals count observed
traffic while the app runs, and reset on manual interface selection or Reset.
Sleep gaps and counter discontinuities establish a fresh baseline.

CPU is aggregate non-idle utilization. Memory is active + wired + physically
compressed RAM, with categories displayed separately; this differs from Activity
Monitor's Memory Used definition. Maximum capacity (macOS) comes from the system power report, loaded in the background
on opening Power and cached for one hour across launches. A separate Raw capacity
estimate is `NominalChargeCapacity / DesignCapacity × 100`, falling back to
`AppleRawMaxCapacity`, truncated to an integer and capped at 100. These are different
measures and can differ substantially. The system report is refreshed when its one-hour cache expires, including within
a long-running app session; failed reads can retry after a minute. It is not
polled with the live metrics.
Battery power preserves signed current: positive is charging, negative is discharging;
near-zero power while on AC is Running on adapter. Watts measure net power at the
battery, rather than total adapter consumption. This also identifies battery
discharge while plugged in. Readings use the one-second power sample while Power is visible. Hardware may
update individual sensor values less frequently than the app samples them.
Time remaining is the hardware estimate. Missing data is shown as unavailable.

## Battery runtime estimates

Power → Battery runtime shows time left at current use and typical full-charge
runtime. These are estimates, independent of the macOS battery-health percentage.

Recent time left is `remaining raw capacity (mAh) / smoothed discharge current (mA)`.
The discharge current uses a time-based exponential average with a 180-second
time constant. When both CPU load changes by more than 15 percentage points and
measured draw changes by over 25%, a 60-second constant adapts faster. CPU is not
converted to watts: measured battery draw already includes CPU, display, GPU,
network and other loads. Smoothed watts and sampled CPU load are displayed.

The recent model needs two minutes of continuous valid discharge observations.
During learning, a valid macOS time estimate is shown with a macOS label when
available. AC operation shows On power adapter and never mistakes charge time for
discharge runtime. Sleep gaps, invalid readings and Low Power Mode transitions
restart the recent model instead of integrating unobserved time.

Typical full-charge runtime is `latest full capacity / average observed discharge
current`. The average is weighted by actual sampled discharge time, using up to
seven daily summaries and at least ten minutes of valid observations. Charging
and sleep are excluded. It is a full-charge equivalent estimate, not a claim that
a complete battery cycle was observed. Only seven small local summaries are saved,
at most once every five minutes plus sleep/quit. No app/process activity is logged.
Predictions are rounded to five minutes and depend on future workload remaining
similar; no remaining-time prediction is fabricated while learning.

## Build and test without global dependencies

Run these commands from the project root (the folder containing `Package.swift`).

Requires Apple's existing Swift 5.9+ Command Line Tools.

```sh
zsh build.sh
zsh test.sh
dist/PulseBar.app/Contents/MacOS/PulseBar --diagnose
python3 Tests/network-smoke.py dist/PulseBar.app/Contents/MacOS/PulseBar
python3 Tests/profile-smoke.py
python3 Tests/profile.py PID --seconds 30 --interval 0.1
```

CPU profiling converts Mach ticks using `mach_timebase_info`; this matters on
Apple Silicon, whose counter ticks are not nanoseconds. The one-core smoke test
catches clock-unit mistakes. The app’s system-CPU ratio, network speeds, ping timing and battery runtime use
separate clocks/readers.

All compiler and package caches stay in `.build-local/`. Override using
`PULSEBAR_BUILD_DIR=/absolute/path`. Delete that directory after building; the
app in `dist/` is standalone. Both directories are excluded from Git. Font assets and their licenses are in Assets/Fonts and get
copied into the app bundle. The build is ad-hoc signed, not publicly notarized.

Developer modes use the same production panel:

```sh
dist/PulseBar.app/Contents/MacOS/PulseBar --snapshot /absolute/path.png --section network
open dist/PulseBar.app --args --show --ui-test
```

`--ui-test` adds a temporary Dock identity for UI inspection; normal mode has no
Dock icon. `--snapshot` uses a separate preference suite and exits after capture.
Normal use stores preferences and bounded local battery runtime summaries. To uninstall, disable
launch at login, quit, and delete the app. Preferences use `local.pulsebar.app`.

## Credits

The 64-bit network reader is adapted from Stats, MIT, by Serhiy Mytrovtsiy.
UI patterns and palettes are based on Omarchy, MIT, by David Heinemeier Hansson
and contributors. Fonts are from Nerd Fonts/JetBrains under SIL OFL. Full notices
are in THIRD-PARTY-NOTICES.md and the app bundle. PulseBar is independent of
Omarchy and Stats.
