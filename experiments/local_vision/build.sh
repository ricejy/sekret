#!/bin/bash
set -euo pipefail
vision_dir="$(cd "$(dirname "$0")" && pwd)"
runtime_dir="$vision_dir/../local_generation/artifacts/build-apple/llama.xcframework/macos-arm64_x86_64"
mkdir -p "$vision_dir/.build"
xcrun clang++ -arch arm64 -std=c++17 -O2 \
  -F "$runtime_dir" -framework llama \
  -Wl,-rpath,"$runtime_dir" \
  "$vision_dir/abi_probe.cpp" -o "$vision_dir/.build/abi-probe"
if [[ -f "$vision_dir/main.mm" ]]; then
  xcrun clang++ -arch arm64 -std=c++17 -O2 -fobjc-arc \
    -F "$runtime_dir" -framework llama -framework Foundation \
    -framework ImageIO -framework CoreGraphics \
    -Wl,-rpath,"$runtime_dir" \
    "$vision_dir/main.mm" -o "$vision_dir/.build/local-vision-eval"
fi
