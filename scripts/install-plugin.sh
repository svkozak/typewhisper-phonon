#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
target="$HOME/Library/Application Support/TypeWhisper/Plugins/PhononPlugin.bundle"
if [[ -e "$target" ]]; then
 echo "Bundle already exists: $target. Move it aside before reinstalling."
 exit 1
fi
mkdir -p "$(dirname "$target")"
ditto build/PhononPlugin.bundle "$target"
echo "Installed. Restart TypeWhisper to load the plugin."
