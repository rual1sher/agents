#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="rualisher.agents"

echo "=== Installing $PLUGIN_NAME ==="

# 1. Create target directories
mkdir -p "$HOME/.config/omarchy/plugins"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/systemd/user"

# 2. Symlink plugin into Omarchy plugins directory
PLUGIN_TARGET="$HOME/.config/omarchy/plugins/$PLUGIN_NAME"
if [ -L "$PLUGIN_TARGET" ] || [ -d "$PLUGIN_TARGET" ]; then
    echo "Updating plugin link at $PLUGIN_TARGET..."
    rm -rf "$PLUGIN_TARGET"
fi
ln -sf "$SCRIPT_DIR" "$PLUGIN_TARGET"
echo "✓ Plugin linked to $PLUGIN_TARGET"

# 3. Install Antigravity (agy) usage collector
chmod +x "$SCRIPT_DIR/bin/omarchy-agent-usage-agy"
ln -sf "$SCRIPT_DIR/bin/omarchy-agent-usage-agy" "$HOME/.local/bin/omarchy-agent-usage-agy"
echo "✓ Collector linked to $HOME/.local/bin/omarchy-agent-usage-agy"

# 4. Install systemd user services & timers for AGY auto-refresh
for unit in "$SCRIPT_DIR"/systemd/*; do
    if [ -f "$unit" ]; then
        ln -sf "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
    fi
done
echo "✓ Systemd units linked to $HOME/.config/systemd/user/"

# 5. Reload systemd & enable units
systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-agy.path omarchy-agent-usage-agy.timer || true

# 6. Run initial collector data collection
if command -v agy >/dev/null 2>&1; then
    echo "Running initial Antigravity usage collection..."
    "$HOME/.local/bin/omarchy-agent-usage-agy" --write 2>/dev/null || true
fi

# 7. Restart Omarchy Shell if available
if command -v omarchy >/dev/null 2>&1; then
    echo "Restarting Omarchy shell..."
    omarchy restart shell || true
fi

echo ""
echo "=== Installation Complete! ==="
echo "Make sure '$PLUGIN_NAME' is added to your bar layout in ~/.config/omarchy/shell.json:"
echo '  "right": ['
echo '    { "id": "'"$PLUGIN_NAME"'" }'
echo '  ]'
