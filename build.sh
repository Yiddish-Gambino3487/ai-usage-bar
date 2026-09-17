#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -swift-version 6 Sources/*.swift -o build/AIUsageBar
echo "built build/AIUsageBar"
