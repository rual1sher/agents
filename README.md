# rualisher.agents — Omarchy AI Agents Bar Plugin

A customized native Omarchy bar plugin and modal panel for monitoring AI coding subscriptions and usage:
- **Antigravity (AGY)**
- **Claude Code**
- **Codex**
- **Fireworks**

---

## Features

- **Wide Horizontal Layout**: 720px wide layout designed along the horizontal axis.
- **Top 2-Column Row**:
  - **Limits & Balance**: Side-by-side with dynamic soft color tiers (<50% green, <75% yellow, <80% orange, $\ge$80% red) and glowing indicators.
  - **Tokens by Day (Bar Chart)**: Vertical growing bar chart showing daily activity over the last 7 days, stretched to match the full height of the Limits section, with soft glow on the active day.
- **Tokens by Model (Full Width)**: Detailed token breakdown with ranked placement badges (`#1`, `#2`, `#3`, `#4`) and soft gold/silver/bronze/muted themes.
- **Manual Data Refresh Button**: Located in the top-right corner of the hero card, aligned with the AI provider title, featuring a spinning refresh animation and keyboard shortcut (<kbd>R</kbd>).
- **Multi-device Sync Support**: Merges usage stats across multiple machines (e.g. desktop + laptop) via Syncthing/Dropbox/rsync.

---

## Installation on a New Machine (Laptop)

### 1. Clone the repository
```bash
git clone <your-repo-url> ~/Projects/rualisher.agents
cd ~/Projects/rualisher.agents
```

### 2. Run the automated installer
```bash
./install.sh
```

This script will:
- Link the plugin into `~/.config/omarchy/plugins/rualisher.agents`
- Install `omarchy-agent-usage-agy` into `~/.local/bin/`
- Install and activate systemd path & timer units for automatic Antigravity data collection
- Reload systemd and restart the Omarchy shell

### 3. Add to Bar Configuration
Ensure `rualisher.agents` is included in your bar layout inside `~/.config/omarchy/shell.json` (or via `omarchy bar` command):

```json
{
  "bar": {
    "sections": {
      "right": [
        { "id": "rualisher.agents" }
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

## Keybindings & Shortcuts

| Action | Shortcut / Click |
|---|---|
| Open / Toggle Panel | Click bar icon or `omarchy-shell omarchy.agents toggle` |
| Switch Provider | <kbd>h</kbd> / <kbd>l</kbd> or Middle-click bar icon |
| Refresh Usage Data | <kbd>r</kbd> / <kbd>Enter</kbd> or Click refresh button in header |
| Scroll | <kbd>j</kbd> / <kbd>k</kbd> / Mouse wheel |
| Close Panel | <kbd>Esc</kbd> |

---

## Structure

```
rualisher.agents/
├── manifest.json                  # Omarchy plugin manifest
├── Main.qml                       # Data watchers and cross-device sync logic
├── Panel.qml                      # Bar widget & horizontal modal panel UI
├── Agent.qml                      # File watcher for JSON usage records
├── assets/                        # SVG icons for providers (agy, claude, codex, fireworks)
├── bin/
│   └── omarchy-agent-usage-agy    # Antigravity CLI usage collector script
├── systemd/                       # Systemd user path/service/timer units
│   ├── omarchy-agent-usage-agy.path
│   ├── omarchy-agent-usage-agy.service
│   └── omarchy-agent-usage-agy.timer
├── install.sh                     # One-click installation & symlinking script
└── README.md
```
