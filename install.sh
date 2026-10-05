#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="rualisher.agents"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Installing / Updating $PLUGIN_NAME ==="

# 1. Create target directories safely
mkdir -p "$HOME/.config/omarchy/plugins"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/systemd/user"

# 2. Safely handle existing plugin folder (backup if it's a real directory)
PLUGIN_TARGET="$HOME/.config/omarchy/plugins/$PLUGIN_NAME"
if [ -d "$PLUGIN_TARGET" ] && [ ! -L "$PLUGIN_TARGET" ]; then
    BACKUP_DIR="${PLUGIN_TARGET}.bak.${TIMESTAMP}"
    echo "⚠️  Existing directory found at $PLUGIN_TARGET."
    echo "📦 Creating backup at $BACKUP_DIR..."
    mv "$PLUGIN_TARGET" "$BACKUP_DIR"
elif [ -L "$PLUGIN_TARGET" ]; then
    echo "Updating existing symlink at $PLUGIN_TARGET..."
    rm -f "$PLUGIN_TARGET"
fi

ln -sf "$SCRIPT_DIR" "$PLUGIN_TARGET"
echo "✓ Plugin linked to $PLUGIN_TARGET"

# 3. Install Antigravity (agy) usage collector
chmod +x "$SCRIPT_DIR/bin/omarchy-agent-usage-agy"

BIN_TARGET="$HOME/.local/bin/omarchy-agent-usage-agy"
if [ -f "$BIN_TARGET" ] && [ ! -L "$BIN_TARGET" ]; then
    echo "📦 Backing up existing binary to ${BIN_TARGET}.bak.${TIMESTAMP}..."
    mv "$BIN_TARGET" "${BIN_TARGET}.bak.${TIMESTAMP}"
fi
ln -sf "$SCRIPT_DIR/bin/omarchy-agent-usage-agy" "$BIN_TARGET"
echo "✓ Collector linked to $BIN_TARGET"

# 4. Install systemd user services & timers for AGY auto-refresh
for unit in "$SCRIPT_DIR"/systemd/*; do
    if [ -f "$unit" ]; then
        UNIT_NAME=$(basename "$unit")
        UNIT_TARGET="$HOME/.config/systemd/user/$UNIT_NAME"
        if [ -f "$UNIT_TARGET" ] && [ ! -L "$UNIT_TARGET" ]; then
            mv "$UNIT_TARGET" "${UNIT_TARGET}.bak.${TIMESTAMP}"
        fi
        ln -sf "$unit" "$UNIT_TARGET"
    fi
done
echo "✓ Systemd units linked to $HOME/.config/systemd/user/"

# 5. Reload systemd & enable units
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now omarchy-agent-usage-agy.path omarchy-agent-usage-agy.timer 2>/dev/null || true
fi

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
echo "=== Done! Nothing was broken. ==="
echo "If you had previous files, automatic backups (.bak.*) were preserved."
echo "Make sure '$PLUGIN_NAME' is added to your bar layout in ~/.config/omarchy/shell.json:"
echo '  "right": ['
echo '    { "id": "'"$PLUGIN_NAME"'" }'
echo '  ]'
