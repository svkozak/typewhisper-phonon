#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
source_dir="$PWD/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
output="$PWD/.build/phonon-metal"
mkdir -p "$output"
# Compile MLX's prepared static kernels. Its other kernels compile on demand.
# Build every prepared source, rather than filtering for one test recording.
while IFS= read -r source; do
    name="${source#"$source_dir/"}"
    name="${name//\//_}"
    xcrun metal -O2 -mmacosx-version-min=14.0 -I "$source_dir" -c "$source" -o "$output/$name.air"
done < <(find "$source_dir" -name '*.metal' -type f | sort)
xcrun metallib "$output"/*.air -o .build/release/mlx.metallib
