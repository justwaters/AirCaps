# AirCaps

macOS CLI tool to switch AirPods Pro noise control modes and manage audio output. Includes an optional [menu-bar app](#menu-bar-app) that lets you toggle noise mode with the Caps Lock key.

## Requirements

- macOS 13+ (Ventura or later)
- AirPods Pro (or other AirPods with ANC/Adaptive/Transparency)
- [Accessibility permission](#accessibility-permission) (for noise mode switching with the `ax` backend; not needed with `hal`)
- Input Monitoring permission (menu-bar app only — see [Menu Bar App](#menu-bar-app))

## Installation

### Homebrew (menu-bar app)

```bash
brew install --cask justwaters/tap/aircaps
```

Or download `AirCaps.dmg` from the [latest release](https://github.com/justwaters/AirCaps/releases/latest). Releases from 1.3.1 on are signed with a Developer ID and notarized by Apple, so the app opens normally. (Earlier releases were ad-hoc signed: on those, use **Open Anyway** in System Settings → Privacy & Security.)

### From source (CLI)

```bash
git clone https://github.com/justwaters/AirCaps.git
cd AirCaps
make install
```

This builds a release binary and copies it to `/usr/local/bin/aircaps`.

## Build

```bash
# Debug build
swift build

# Release build
swift build -c release

# Or using the Makefile
make build       # debug
make release     # release
make install     # release + install to /usr/local/bin
make clean       # remove build artifacts
make uninstall   # remove from /usr/local/bin
```

## Usage

```
aircaps [command]
```

### Commands

| Command  | Description                                    |
| -------- | ---------------------------------------------- |
| `status` | Show AirPods connection, audio, and battery    |
| `on`     | Switch audio output to AirPods                 |
| `off`    | Switch audio output to built-in speakers       |
| `toggle` | Toggle between AirPods and built-in speakers   |
| `list`   | List all audio devices and Bluetooth devices   |
| `ANC`    | Set noise control to Active Noise Cancellation |
| `AT`     | Set noise control to Adaptive                  |
| `TR`     | Set noise control to Transparency              |

If no command is given, `status` is the default.

### Examples

```bash
# Check AirPods status and battery
aircaps status

# Switch audio to AirPods
aircaps on

# Enable noise cancellation
aircaps ANC

# Enable adaptive mode
aircaps AT

# Enable transparency mode
aircaps TR

# Toggle back to built-in speakers
aircaps off
```

## How it works

### Noise Control

Noise mode switching (ANC/AT/TR) has two backends, chosen with `--backend ax|hal` on the CLI (default `ax`) or in the menu-bar app's Settings (default CoreAudio).

**`hal` — CoreAudio listening mode.** Writes the private CoreAudio property `'lstm'` on the AirPods audio device, then reads it back to confirm the mode changed. It needs no Accessibility permission. It uses an undocumented API, so a macOS update could break it. The technique comes from [pods-control](https://github.com/raulgg/pods-control) (MIT).

**`ax` — Accessibility.** Uses the macOS Accessibility API. The tool:

1. Opens Control Center's Sound menu bar popover
2. Expands the AirPods section to reveal Listening Mode controls
3. Clicks the target mode checkbox (Noise Cancellation, Adaptive, or Transparency)
4. Closes the popover

This approach exists because Apple removed the private `NoiseCore.framework` API and the L2CAP/AAP Bluetooth protocol is locked down on recent macOS versions, making BLE-based control unavailable without special permissions.

### Audio Output

Audio device switching uses CoreAudio APIs (`AudioObjectSetPropertyData`) to change the default and system output devices.

### Battery Info

Battery levels are parsed from `system_profiler SPBluetoothDataType` output.

## Accessibility Permission

The noise mode commands (`ANC`, `AT`, `TR`) require Accessibility access when run with `--backend ax`. The `hal` backend does not. On first run, you'll see a prompt. To grant it manually:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the '+' button and add Terminal (or your terminal emulator)
3. If using the binary directly, add `/usr/local/bin/aircaps` (you may need to add your terminal and run from there)

The audio and status commands (`on`, `off`, `toggle`, `status`, `list`) do not require accessibility permissions.

## Project Structure

```
AirCaps/
├── Package.swift          # SPM package manifest (3 targets)
├── Makefile                # Build/install targets, incl. menu-bar app bundling
├── Packaging/
│   └── Info.plist          # Menu-bar app bundle metadata (LSUIElement, etc.)
├── Sources/
│   ├── AirPodsCore/         # Shared library: audio, Bluetooth, battery, AX noise
│   │   │                    # control — used by both the CLI and the menu-bar app
│   │   ├── AudioDevices.swift
│   │   ├── Battery.swift
│   │   ├── Bluetooth.swift
│   │   ├── CoreError.swift
│   │   ├── NoiseControl.swift
│   │   └── Permissions.swift
│   ├── aircaps/              # CLI — thin wrapper around AirPodsCore
│   │   └── main.swift
│   └── AirCapsApp/          # Menu-bar app (see below), target named "…App" to
│       │                    # avoid colliding with Sources/aircaps/ on
│       │                    # case-insensitive filesystems — the app itself is
│       │                    # still named "AirCaps" (see Packaging/Info.plist)
│       ├── AirCapsApp.swift
│       ├── CapsLockController.swift
│       ├── MenuContent.swift
│       ├── NoiseModeController.swift
│       ├── PermissionsGate.swift
│       ├── SettingsStore.swift
│       ├── SettingsView.swift
│       └── UpdateChecker.swift
└── README.md
```

- **CoreAudio** — audio device enumeration and switching
- **IOBluetooth** — Bluetooth device detection
- **ApplicationServices** — Accessibility (AX) API for UI automation
- **IOKit** (HID) — raw keyboard input capture and LED control (menu-bar app only)
- **system_profiler** — battery level parsing

## Custom SF Symbols

`Packaging/SFSymbols/` holds the three mode icons (`aircaps.noise.cancellation`, `aircaps.adaptive`, `aircaps.transparency`) as SF Symbols custom-symbol templates. In the SF Symbols app, use **File → Import Symbol…** (or drag the SVGs in). The same artwork is used for every weight and size, so refine the Ultralight and Black masters there if you need a true weight range.

## Menu Bar App

`AirCaps.app` is a persistent menu-bar app built on the same `AirPodsCore` logic as the CLI. It repurposes the physical **Caps Lock key** as a hardware toggle for AirPods noise mode:

- **LED on** → Noise Cancellation
- **LED off** → Adaptive or Transparency, whichever you pick in Settings

Pressing Caps Lock (on the built-in keyboard or any connected Apple Magic Keyboard) toggles between the two, and the LED state is kept in sync across every connected keyboard. The menu-bar dropdown also mirrors the CLI's audio-switching commands (`on`/`off`/`toggle`).

### How Caps Lock capture works

Caps Lock's lock/LED behavior is normally owned by macOS below the application layer, so using it as a custom trigger means going underneath that:

1. On launch, the app applies a system-wide `hidutil` remap that turns Caps Lock into a no-op key — this stops normal text-input caps-locking and stops the OS from auto-driving the LED.
2. It separately watches for raw physical Caps Lock key-down events via `IOHIDManager`, independent of the remap.
3. It owns the LED explicitly from then on, writing it to every connected keyboard whenever the mode changes, and syncing any newly-connected keyboard immediately.
4. Quitting the app (via its **Quit** menu item) reverts the remap so Caps Lock goes back to normal.

**Known limitation**: the revert only runs on a clean quit. Force-killing the process (Activity Monitor "Force Quit", `killall`, a crash) skips it, leaving Caps Lock inert until you relaunch-and-quit the app properly, reboot, or manually run:
```bash
hidutil property --set '{"UserKeyMapping":[]}'
```

### Permissions

The menu-bar app needs two permissions beyond what the CLI requires:

- **Accessibility** — only when the Settings backend is "Control Center (Accessibility)". The default CoreAudio backend does not need it.
- **Input Monitoring** — new, required for `IOHIDManager` to observe raw keyboard input. the app's menu shows a "Grant Input Monitoring…" button that opens **System Settings → Privacy & Security → Input Monitoring** when it's missing. If AirCaps isn't listed there, click **+** and add `AirCaps.app` manually.

Both are re-checked every time the menu opens, so granting them mid-session (without restarting the app) works.

### Hiding the menu bar icon

Settings → Menu Bar → **Show menu bar icon** turns the icon off; Caps Lock keeps working. Launching AirCaps again (Spotlight or Finder) opens Settings. Menu bar managers such as Hidden Bar can also hide the icon while collapsed.

### Release build

`make dist` builds the release DMG: it signs the app with the Developer ID Application certificate (hardened runtime), notarizes it through Xcode's signed-in Apple ID using `Packaging/notarize.sh`, staples the ticket and packages a signed `AirCaps.dmg`. It needs Xcode signed in to the team and takes a couple of minutes while Apple processes the upload.

### Build & Install

```bash
# Build and wrap into a minimal .app bundle (ad-hoc signed)
make bundle

# Same, plus copies it to /Applications
make bundle-install

# Remove from /Applications
make bundle-uninstall
```

Launch `AirCaps.app` from `/Applications` (or Spotlight) — it runs as a menu-bar-only app with no Dock icon. Open its **Settings…** to choose Adaptive vs. Transparency for the LED-off state and to enable Launch at Login.

### Updates

The menu's **Check for Updates…** item queries the GitHub Releases API on demand and, if a newer tagged version is out, offers to **Install Update** (or open the release page). Installing downloads `AirCaps.dmg`, checks it is AirCaps at the expected version, quits the app, swaps the bundle in place and relaunches it. It needs write access to the folder AirCaps is installed in, and macOS keeps your Input Monitoring grant across updates between Developer ID-signed releases. There's no background polling — checking only happens when you click it.

Note: local `make bundle` builds are ad-hoc signed, so Accessibility/Input Monitoring grants may need to be re-approved after each rebuild, since the code identity changes per build. Release builds (`make dist`) keep a stable Developer ID identity, so grants carry over between releases signed this way.
