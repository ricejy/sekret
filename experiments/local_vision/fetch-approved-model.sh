#!/bin/bash
set -euo pipefail
vision_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$vision_dir/artifacts" "$vision_dir/results"
free_kib="$(df -k "$vision_dir" | tail -1 | awk '{print $4}')"
if [[ "$free_kib" -lt 2621440 ]]; then
  echo 'Need at least 2.5 GiB free before retrieving the approved pair.' >&2
  exit 1
fi
base='https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/72e986006ef53e37cdd3f6d4241c90b0f01df376'
fetch_one() {
  local name="$1" bytes="$2" digest="$3"
  local target="$vision_dir/artifacts/$name"
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
fetch_one SmolVLM-500M-Instruct-Q8_0.gguf 436806912 9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4
fetch_one mmproj-SmolVLM-500M-Instruct-Q8_0.gguf 108783360 d1eb8b6b23979205fdf63703ed10f788131a3f812c7b1f72e0119d5d81295150
curl --fail --location --output "$vision_dir/artifacts/gguf-model-card.md" "$base/README.md"
curl --fail --location --output "$vision_dir/artifacts/publisher-model-card.md" 'https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct/resolve/a7da5b986cb59b408707209984f360a5f4ad7e47/README.md'
curl --fail --location --output "$vision_dir/artifacts/Apache-2.0.txt" 'https://www.apache.org/licenses/LICENSE-2.0.txt'
