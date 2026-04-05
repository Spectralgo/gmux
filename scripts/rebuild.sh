#!/bin/bash
# Rebuild and restart Gmux app

set -e

cd "$(dirname "$0")/.."

# Kill existing app if running
pkill -9 -f "Gmux" 2>/dev/null || true

# Build
swift build

# Copy to app bundle
cp .build/debug/cmux .build/debug/Gmux.app/Contents/MacOS/

# Open the app
open .build/debug/Gmux.app
