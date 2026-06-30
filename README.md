# airpodsctl

macOS CLI tool to switch AirPods Pro noise control modes and manage audio output.

## Requirements

- macOS 13+ (Ventura or later)
- AirPods Pro (or other AirPods with ANC/Adaptive/Transparency)
- [Accessibility permission](#accessibility-permission) (for noise mode switching)

## Installation

```bash
git clone https://github.com/your-username/airpodsctl.git
cd airpodsctl
make install
```

This builds a release binary and copies it to `/usr/local/bin/airpodsctl`.

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
airpodsctl [command]
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
| `AT`     | Set noise control to Adaptive Transparency     |
| `TR`     | Set noise control to Transparency              |

If no command is given, `status` is the default.

### Examples

```bash
# Check AirPods status and battery
airpodsctl status

# Switch audio to AirPods
airpodsctl on

# Enable noise cancellation
airpodsctl ANC

# Enable adaptive transparency
airpodsctl AT

# Enable transparency mode
airpodsctl TR

# Toggle back to built-in speakers
airpodsctl off
```

## How it works

### Noise Control

Noise mode switching (ANC/AT/TR) works via the macOS Accessibility API. The tool:

1. Opens Control Center's Sound menu bar popover
2. Expands the AirPods section to reveal Listening Mode controls
3. Clicks the target mode checkbox (Noise Cancellation, Adaptive, or Transparency)
4. Closes the popover

This approach is used because Apple removed the private `NoiseCore.framework` API and the L2CAP/AAP Bluetooth protocol is locked down on recent macOS versions, making BLE-based control unavailable without special permissions.

### Audio Output

Audio device switching uses CoreAudio APIs (`AudioObjectSetPropertyData`) to change the default and system output devices.

### Battery Info

Battery levels are parsed from `system_profiler SPBluetoothDataType` output.

## Accessibility Permission

The noise mode commands (`ANC`, `AT`, `TR`) require Accessibility access. On first run, you'll see a prompt. To grant it manually:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the '+' button and add Terminal (or your terminal emulator)
3. If using the binary directly, add `/usr/local/bin/airpodsctl` (you may need to add your terminal and run from there)

The audio and status commands (`on`, `off`, `toggle`, `status`, `list`) do not require accessibility permissions.

## Project Structure

```
airpodsctl/
├── Package.swift          # SPM package manifest
├── Makefile               # Build/install targets
├── Sources/
│   └── airpodsctl/
│       └── main.swift     # Single-source implementation
└── README.md
```

The entire tool is a single Swift file for simplicity:

- **CoreAudio** — audio device enumeration and switching
- **IOBluetooth** — Bluetooth device detection
- **ApplicationServices** — Accessibility (AX) API for UI automation
- **system_profiler** — battery level parsing
