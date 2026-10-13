# rualisher.sysmon — Omarchy System Monitor Bar Plugin

A native Omarchy bar widget and popup panel for real-time system resource monitoring.

This plugin is completely independent of `rualisher.agents`.

---

## What It Shows

- **CPU %**: Real-time overall and per-core CPU utilization
- **CPU temperature**: Thermal sensor readings via hwmon
- **RAM %**: Memory utilization (used / total, available, cached, buffers, and swap)
- **Load averages**: 1, 5, and 15-minute system load averages
- **Top processes**: Ranked process inspection sorted by %CPU and RSS memory

---

## Installation

Run the installer script:

```bash
./install.sh
```

This script will:
- Link the plugin into `~/.config/omarchy/plugins/rualisher.sysmon`
- Back up an existing plugin directory as `.bak.<timestamp>`
- Restart the Omarchy shell

---

## Bar Configuration

Add `{ "id": "rualisher.sysmon" }` to the `right` section of `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "sections": {
      "right": [
        { "id": "rualisher.sysmon" }
      ]
    }
  }
}
```

Then restart the shell:

```bash
omarchy restart shell
```

---

## Structure

```
sysmon/
├── manifest.json   # Omarchy plugin manifest
├── BarWidget.qml   # Bar widget item and background metrics collector
├── Panel.qml       # Detailed popup panel UI
├── install.sh      # Symlink and installation script
└── README.md       # Plugin documentation
```
