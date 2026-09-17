#!/bin/zsh
# Stops the app and removes the LaunchAgent. Source and build directory stay in place.
set -euo pipefail
label=local.ai-usage-bar
launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
rm -f ~/Library/LaunchAgents/$label.plist
echo "removed $label"
