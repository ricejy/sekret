#!/bin/bash
set -euo pipefail
eval_dir="$(cd "$(dirname "$0")" && pwd)"
runtime="$eval_dir/artifacts/llama.xcframework/macos-arm64_x86_64"
mkdir -p "$eval_dir/.build/diagnostic"
xcrun clang++ -arch arm64 -std=c++17 -O2 -fobjc-arc \
  -F "$runtime" -framework llama -framework Foundation \
  -Wl,-rpath,"$runtime" "$eval_dir/diagnostic_control.mm" \
  -o "$eval_dir/.build/diagnostic/control"
