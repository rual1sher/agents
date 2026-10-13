#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="rualisher.sysmon"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Installing / Updating $PLUGIN_NAME ==="

# 1. Create target directories safely
mkdir -p "$HOME/.config/omarchy/plugins"

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

# 3. Restart Omarchy Shell if available
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
