# App Store Listing & Submission Notes

Everything App Store Connect asks for, ready to paste. Field limits were checked by script.

## App information

| Field | Value |
|---|---|
| Name | Resource Tracker _(names must be unique on the store — have a fallback such as "Resource Tracker – System Monitor")_ |
| Subtitle (28/30) | Live CPU, GPU & memory stats |
| Bundle ID | `com.hassan.ResourceTracker` |
| Primary category | Utilities |
| Secondary category | Developer Tools |
| Age rating | 4+ (no objectionable content) |
| Copyright | © 2026 Hassan Raza Shaikh |
| Privacy Policy URL | https://github.com/Hassan-Raza-Shaikh/Resource_Tracker/blob/main/PRIVACY.md |
| Support URL | https://github.com/Hassan-Raza-Shaikh/Resource_Tracker/issues |

**App Privacy questionnaire:** answer **"No, we do not collect data from this app."** No data types, no tracking.

**Export compliance:** handled by `ITSAppUsesNonExemptEncryption = NO` in Info.plist — no prompt on upload.

## Promotional text (152/170)

See what your Mac is doing at a glance: CPU, GPU, memory pressure, disk and network, in a Liquid Glass dashboard, a menu bar summary and a floating HUD.

## Keywords (99/100)

```
system monitor,activity,cpu,gpu,memory,ram,pressure,network,bandwidth,disk,performance,menu bar,hud
```

## Description

Resource Tracker shows what your Mac is doing, right now, without getting in the way.

A calm, native dashboard built with Liquid Glass brings every vital sign together: processor load and per-core activity, GPU utilization, memory, disk and network throughput, and your Mac's thermal state — each with a live 30-second history.

HONEST ABOUT MEMORY
macOS keeps RAM full on purpose, so "percent used" says little. Resource Tracker leads with memory pressure — the same signal Activity Monitor uses — so it only raises a flag when your Mac is genuinely struggling.

ALWAYS WITHIN REACH
• A menu bar summary of CPU, memory, GPU and network
• An optional floating HUD that stays visible over full-screen apps
• A plain-language status line: "Cruising smoothly", or what needs attention

SEE WHAT'S BUSY
Top Processes lists the 50 busiest processes running under your account, with icons, sortable by CPU or memory.

LIGHT ON YOUR MAC
A monitor shouldn't cost what it measures. Resource Tracker samples once a second, redraws only what changed, and does almost nothing while its window is hidden.

PRIVATE BY DESIGN
No accounts, no analytics, no network access. Everything stays on your Mac.

Requires macOS 26 or later.

## Screenshots

16:10, one of: 1280×800, 1440×900, 2560×1600, 2880×1800. Suggested set:
1. Dashboard (light)
2. Dashboard (dark)
3. Top Processes
4. Memory — pressure explained
5. CPU cores
6. Menu bar summary + HUD over a full-screen app

## Notes for App Review

> Resource Tracker is a sandboxed system monitor. It reads statistics through public APIs only — Mach host statistics (`host_processor_info`, `host_statistics64`), `sysctl`, the IOKit registry (block-storage and accelerator statistics), `getifaddrs`, `proc_pidinfo`, and `NSRunningApplication` — and displays them on screen. It collects no data and has no network access.
>
> To review: the main window opens at launch. The sidebar switches between Dashboard, Top Processes, CPU, GPU, Memory, Disk and Network. "Show HUD" (top right of the Dashboard) opens a floating always-on-top readout; right-click it to hide it. The chart icon in the menu bar opens a summary. Settings (⌘,) holds Open at Login (via `SMAppService`) and the HUD toggle.
>
> Top Processes intentionally shows only processes owned by the current user: other users' processes are not readable from the App Sandbox. The app has no ability to quit or signal other processes.

## Before each upload

- Bump `CFBundleVersion` in `Info.plist` (and `CFBundleShortVersionString` for a new version).
- `xcodebuild test` passes.
- Product ▸ Archive ▸ Distribute App ▸ App Store Connect.
