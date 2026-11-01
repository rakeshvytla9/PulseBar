# Omarchy → PulseBar on macOS

Reference: Omarchy `quattro`, commit `bda3aaf6955404712dbd46541e6c8a75a2b16b7c`,
particularly `shell/Commons/Style.qml`, `shell/plugins/panels/` and
[the top-bar manual](https://github.com/omacom/omarchy/blob/quattro/manual/05-the-top-bar.md).

PulseBar ports the control-center interactions to macOS APIs. Omarchy's QML,
PipeWire, NetworkManager, BlueZ and Hyprland services cannot run as a native
macOS menu bar widget. The boundaries below are explicit rather than presenting
non-working controls.

| Omarchy function | PulseBar behavior |
| --- | --- |
| Font and icon glyphs | Exact JetBrainsMono Nerd Font, Regular and Bold, bundled inside the app; process-only registration |
| Panel style | Neutral native translucent appearance by default; compact rounded surfaces and per-panel heights; classic theme palettes are optional |
| Independent panel navigation | Dedicated Wi-Fi, Traffic, Audio, Display, Power, System, Media, Calendar, World clocks, Weather and Customize pages |
| Keyboard navigation | Native Tab/Shift-Tab and controls, Escape to dismiss, Command-Control-A/N/D/P; optional global shortcuts in Customize |
| Master audio | Real output volume, mute, output selection and sample rate via Core Audio |
| Microphone | Real input level, mute where the device exposes it, input selection; no recording |
| Per-app audio mixer | Not included. Requires a separate macOS audio-routing/tap engine; no audio driver is installed |
| Wi-Fi | Connection-first panel, radio switch, fresh scan on every opening/Refresh and every ten seconds while visible, current network, password join and disconnect |
| Ping and outage detection | Matching Download/Upload/Ping cards, labeled footer Ping shortcut and Connection Quality entry; automatic non-privileged IPv4 ICMP latency; click for jitter, packet loss, average RTT and observed outage durations; route monitoring and two-round TLS connectivity checks separate local association from internet reachability |
| Traffic / network attributes | IPv4/IPv6, DNS, gateway, selected interface, live speeds, graph, launch-session totals |
| DNS providers | Current DNS is displayed; editing opens macOS Network settings to handle privileged changes |
| Brightness | Per-screen real slider where the macOS DisplayServices interface is available; hardware/settings fallback otherwise |
| Resolution, arrangement, Night Shift | Screen attributes shown; changes open macOS Display settings |
| Display text scaling | PulseBar uses Omarchy's default typography. System-wide text scaling is managed by macOS |
| Battery runtime | Smoothed remaining runtime at current draw; learned typical full-charge equivalent from bounded discharge-only history; CPU-guided smoothing, macOS fallback while learning |
| Battery attributes | Charge, native menu symbols and percentage, charging/AC state, macOS-reported maximum capacity, separately labeled raw capacity estimate, cycles, voltage, temperature, signed battery power with charging/discharging/adapter state, estimated time |
| Power profiles | Current Low Power Mode shown; energy-mode changes open macOS Battery settings |
| Stay awake | Real IOKit idle-sleep assertion, released on quit; no daemon or helper |
| Sleep | Native IOKit sleep action, invoked only on click |
| System details | CPU user/system/idle, per-core load, load averages, thermal state, RAM categories, swap and pressure |
| Media | Explicit Music/Spotify track read and previous/play-pause/next controls; macOS Automation permission applies |
| Calendar | Month navigation, day selection, ISO week numbers, Today and Calendar app |
| World clocks | Add/remove system time-zone identifiers and city search, persistent list |
| Weather | Explicit city forecast, current temperature/humidity/wind and five days; Open-Meteo attribution |
| Theme selection | macOS Glass default; optional Tokyo Night, Gruvbox, Everforest, Catppuccin |
| Login startup | Registered through macOS SMAppService; no privileged helper or LaunchAgent file |
| Bottom controls | Live brightness and sound sliders; CPU/RAM and charge remain on their tiles |
| Separate menu bar widgets | Control Center, Traffic, Wi-Fi, Battery; optional audio/display/CPU/memory |
| Remove unused modules | Independent persistent show/hide switches for menu bar items and control center tiles |
| Icon ordering | Separate native macOS status items; Command-drag ordering on Sequoia, with macOS spacing |
| Copy stats | Click individual values or copy a panel summary to the local clipboard |
| Workspaces, tray, notification daemon, lock screen, system-wide OSD | Remain managed by macOS; PulseBar does not replace the operating-system shell |
| Optional Tailscale, Dropbox, AI-provider account panels | Not included; no accounts connected or services installed |

A private, runtime-checked macOS interface is used for display brightness. Apple can change these interfaces; unavailable features
retain a native settings link. This is a local build, not an App Store package.

Monitoring data remains on the Mac. Enabled internet checks contact Cloudflare/Google every five seconds while a panel is open (30 seconds in the background); ICMP pings run every two seconds while open (30 seconds in the background). Opening requests fresh probes; in-flight work is never duplicated. Explicit weather requests contact Open-Meteo.
Wi-Fi names may require Location access, media control may require Automation access. These are requested
only from their corresponding user actions. No global fonts or libraries are installed.

Bluetooth, AirDrop, Focus and Screen Mirroring are intentionally left to macOS rather than provided as duplicate handoff panels. No Accessibility or Bluetooth permission is requested.
