#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 6 Sources/Model.swift Tests/main.swift -o build/tests
./build/tests
