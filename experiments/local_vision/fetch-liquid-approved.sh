#!/bin/bash
set -euo pipefail
vision_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$vision_dir/artifacts/liquid" "$vision_dir/results/liquid-development-v1"
free_kib="$(df -k "$vision_dir" | tail -1 | awk '{print $4}')"
# 1.704 GiB pair + 1.5 GiB reserve + allowance for parallel text artifact/build.
if [[ "$free_kib" -lt 4718592 ]]; then
  echo 'Need at least 4.5 GiB free before retrieving this approved pair.' >&2
  exit 1
fi
base='https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/36fc16bc95133424921bcc3da009e83b2f23ffb5'
fetch_one() {
  local name="$1" bytes="$2" digest="$3"
  local target="$vision_dir/artifacts/liquid/$name"
  if [[ ! -f "$target" ]]; then
    curl --fail --location --retry 2 --output "$target.part" "$base/$name"
    [[ "$(stat -f %z "$target.part")" == "$bytes" ]]
    [[ "$(shasum -a 256 "$target.part" | awk '{print $1}')" == "$digest" ]]
    mv "$target.part" "$target"
  fi
  [[ "$(stat -f %z "$target")" == "$bytes" ]]
  [[ "$(shasum -a 256 "$target" | awk '{print $1}')" == "$digest" ]]
  echo "Verified $name ($bytes bytes)"
}
fetch_one LFM2.5-VL-1.6B-Q8_0.gguf 1246254880 a34bd1506a298d7ff07902e69baeac48c7c20bb85162e61218b743dc10be7c67
fetch_one mmproj-LFM2.5-VL-1.6b-Q8_0.gguf 583109888 2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d
curl --fail --location --output "$vision_dir/artifacts/liquid/LICENSE" "$base/LICENSE"
curl --fail --location --output "$vision_dir/artifacts/liquid/model-card.md" "$base/README.md"
curl --fail --location --output "$vision_dir/artifacts/liquid/chat_template.jinja" 'https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B/resolve/919fde3d022e3f90a4716006f993938ee8c2eb97/chat_template.jinja'
curl --fail --location --output "$vision_dir/artifacts/liquid/processor_config.json" 'https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B/resolve/919fde3d022e3f90a4716006f993938ee8c2eb97/processor_config.json'
