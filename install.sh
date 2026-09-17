#!/bin/zsh
# Installs a LaunchAgent so the menubar app starts at login and restarts if it crashes.
# Quit from the menu exits cleanly and is not restarted. Re-run after ./build.sh to relaunch.
set -euo pipefail
cd "$(dirname "$0")"
label=com.dbaron.ai-usage-bar
plist=~/Library/LaunchAgents/$label.plist
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$PWD/build/AIUsageBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardErrorPath</key><string>$PWD/build/stderr.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$plist"
echo "installed and started $label"
