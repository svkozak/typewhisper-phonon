#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
target="$HOME/Library/Application Support/TypeWhisper/Plugins/PhononPlugin.bundle"
source_bundle=build/PhononPlugin.bundle
[[ -f "$source_bundle/Contents/MacOS/PhononPlugin" && -x "$source_bundle/Contents/Resources/Native/PhononSwift" ]] || { echo 'Build the complete plugin first.'; exit 1; }
codesign --verify --deep --strict "$source_bundle"
if pgrep -x TypeWhisper >/dev/null; then
    echo 'Quit TypeWhisper before installing the plugin.'; exit 1
fi
if [[ -e "$target" && "${1:-}" != --replace ]]; then
    echo 'Bundle already exists. Use --replace to keep a backup and install the new build.'; exit 1
fi
mkdir -p "$(dirname "$target")"
stage=$(mktemp -d "${target}.stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$source_bundle" "$stage"
codesign --verify --deep --strict "$stage"
backup=''
if [[ -e "$target" ]]; then
    backup_dir="$HOME/Library/Application Support/TypeWhisper/PluginBackups"
    mkdir -p "$backup_dir"
    backup="$backup_dir/PhononPlugin-$(date +%Y%m%d-%H%M%S)-$$.bundle"
    mv "$target" "$backup"
fi
if ! mv "$stage" "$target"; then
    [[ -z "$backup" ]] || mv "$backup" "$target"
    exit 1
fi
echo 'Installed. Enable Phonon in TypeWhisper; the server starts automatically.'
[[ -z "$backup" ]] || echo "Previous bundle saved at: $backup"
